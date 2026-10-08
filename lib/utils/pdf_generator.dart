import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csuatlasf/utils/app_utils.dart';

class GPOAPdfGenerator {
  static final Map<int, pw.TableColumnWidth> _folioWidths = {
    0: const pw.FixedColumnWidth(110),
    1: const pw.FixedColumnWidth(75),
    2: const pw.FixedColumnWidth(100),
    3: const pw.FixedColumnWidth(95),
    4: const pw.FixedColumnWidth(95),
    5: const pw.FixedColumnWidth(45),
    6: const pw.FixedColumnWidth(80),
    7: const pw.FixedColumnWidth(65),
    8: const pw.FixedColumnWidth(65),
    9: const pw.FixedColumnWidth(65),
    10: const pw.FixedColumnWidth(75),
  };

  static Future<pw.Document> generateGPOADocument({
    required Map<String, dynamic> organization,
    required List<Map<String, dynamic>> activities,
    required Map<String, dynamic>? president,
    required Map<String, dynamic>? adviser,
    PdfPageFormat format = PdfPageFormat.a4, 
  }) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();
    
    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
      italic: fontItalic,
    );
    
    pw.ImageProvider? logo, iso, pilipinasImage, stars, aun, bldg;
    
    try { logo = await imageFromAssetBundle('assets/images/csulogo.png'); } catch (_) {}
    try { iso = await imageFromAssetBundle('assets/images/iso_pab.png'); } catch (_) {}
    try { pilipinasImage = await imageFromAssetBundle('assets/images/bagong_pilipinas.png'); } catch (_) {}
    try { stars = await imageFromAssetBundle('assets/images/qs_stars.png'); } catch (_) {}
    try { aun = await imageFromAssetBundle('assets/images/aun_qa.png'); } catch (_) {}
    try { bldg = await imageFromAssetBundle('assets/images/vision_mission_building.png'); } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          final rawOrgName = (organization['name'] ?? 'NAME OF ORGANIZATION').toString().toUpperCase();
          final formattedOrgName = rawOrgName.replaceAll('(', '').replaceAll(')', '').trim();
          final redColor = PdfColor.fromHex('#B71C1C');

          final orgType = (organization['type'] ?? '').toString().toLowerCase();
          final isCampus = orgType.contains('campus');
          final isSpecialized = orgType.contains('specialized') || orgType.contains('special');

          final campusHeader = isSpecialized ? 'ANDREWS CAMPUS' : (isCampus ? 'Central Administration' : 'LAL-LO CAMPUS');
          final locationHeader = isSpecialized ? 'Caritan, Tuguegarao City, Cagayan' : (isCampus ? 'Caritan, Tuguegarao City, Cagayan' : 'Sta. Maria, Lal-lo, Cagayan');
          final emailHeader = isSpecialized ? 'osdw@csu.edu.ph' : (isCampus ? 'osdw@csu.edu.ph' : 'osdw.lallo@csu.edu.ph');
          final fbHeader = isSpecialized ? 'Ossw Andrews' : (isCampus ? 'CSU Office of Student Development & Welfare' : 'Osdw Lallo');

          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('CAGAYAN STATE UNIVERSITY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: redColor)),
                        pw.Text('REPUBLIC OF THE PHILIPPINES', style: pw.TextStyle(fontSize: 8, color: redColor)),
                        pw.Text(campusHeader, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: redColor)),
                        pw.Text(locationHeader, style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic)),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 60,
                    child: pw.Center(
                      child: logo != null ? pw.Container(height: 55, width: 55, child: pw.Image(logo)) : pw.SizedBox(width: 55, height: 55),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('Email Address: $emailHeader', style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic)),
                        pw.Text('Website: www.csu.edu.ph', style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic, decoration: pw.TextDecoration.underline)),
                        pw.Text('Facebook Page: $fbHeader', style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  formattedOrgName,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1.5, color: PdfColors.black),
              pw.SizedBox(height: 8),
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
                  if (pilipinasImage != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 5), child: pw.Image(pilipinasImage, height: 32)),
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
            pw.Table(
              border: const pw.TableBorder(
                left: pw.BorderSide(width: 0.5), right: pw.BorderSide(width: 0.5),
                top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5),
                verticalInside: pw.BorderSide(width: 0.5), horizontalInside: pw.BorderSide(width: 0.5),
              ),
              columnWidths: _folioWidths,
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _headerCell('PROGRAM/\nACTIVITIES/\nPROJECT'),
                    _headerCell('SDG\naddressed'),
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

// =======================================================
// OFFICIAL EVALUATION SHEET PDF GENERATOR
// =======================================================

class CSCEvaluationPdfGenerator {
  static Future<pw.Document> generateEvaluationPdf({
    required Map<String, dynamic> organization,
    required String schoolYear,
    required Map<String, double> scores,
    required Map<String, String> gridValues,
    required double grandTotal,
    required String adjectivalRating,
    String orgType = 'College Student Council',
  }) async {
    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
      italic: fontItalic,
    );

    pw.ImageProvider? logo;
    try { logo = await imageFromAssetBundle('assets/images/csulogo.png'); } catch (_) {}

    final typeLower = orgType.toLowerCase();
    final isCampus = typeLower.contains('campus');
    final isSpecialized = typeLower.contains('specialized') || typeLower.contains('special');
    
    final councilLabel = isSpecialized
        ? 'SPECIALIZED ORGANIZATION'
        : (isCampus ? 'CAMPUS STUDENT COUNCIL' : 'COLLEGE STUDENT COUNCIL');
    
    final orgName = organization['name']?.toString().toUpperCase() ?? 'ORGANIZATION NAME';

    if (isSpecialized) {
      // 4-PAGE SPECIALIZED ORGANIZATION PDF GENERATION
      // Page 1
      pdf.addPage(_buildPage(
        pageNumber: 1,
        theme: theme,
        logo: logo,
        isCampus: false,
        isSpecialized: true,
        councilLabel: councilLabel,
        content: [
          _buildDocHeader('CRITERIA FOR THE SEARCH FOR OUTSTANDING $councilLabel SY $schoolYear'),
          pw.SizedBox(height: 15),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Organization: $orgName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text('Points: ${grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Campus: ANDREWS CAMPUS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text('Adjectival Rating: ${adjectivalRating.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Center(child: pw.Text('ACTIVITIES CONDUCTED/ SPONSORED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, decoration: pw.TextDecoration.underline))),
          pw.SizedBox(height: 10),
          _buildSpecializedPage1Matrix(scores, gridValues),
          pw.SizedBox(height: 10),
          pw.Text('For Items III, IV, V and VI, the number of SDGs is no longer required, as discussed during the OSDW 3rd Quarter Meeting held last August 15, 2024. All activities under these items are now considered specific and aligned with their respective objectives.', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _buildCategoricalPdfHeader(false),
          _buildActivityCategoryPdfTable(
            title: 'III. Makakalikasan/ Clean and Green Activities and Projects (10 points)\nMax. No. of Activities: 10',
            docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU\n• Consent letter/Invitation Letter\n• Narrative Report\n• Certificate signed by partner agency\n• Attendance Sheet\n• Documentation',
            key: 'iii',
            gridValues: gridValues,
            maxActs: 10,
            isSDGMatrix: false,
          ),
        ],
      ));

      // Page 2
      pdf.addPage(_buildPage(
        pageNumber: 2,
        theme: theme,
        logo: logo,
        isCampus: false,
        isSpecialized: true,
        councilLabel: councilLabel,
        content: [
          _buildCategoricalPdfHeader(false),
          _buildActivityCategoryPdfTable(
            title: 'IV. Extension Services Sponsored/ Conducted (10 points)\nMax. No. of Activities: 5',
            docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU/ Barangay Resolution\n• Consent/Invitation Letter\n• Narrative report\n• Partner Certificate\n• Attendance Sheet\n• Documentation',
            key: 'iv',
            gridValues: gridValues,
            maxActs: 5,
            isSDGMatrix: false,
          ),
          pw.SizedBox(height: 8),
          pw.Text('Note: For activities conducted with co-sponsor, the points will be divided equally. Any Regional Activity conducted should have CHED Endorsement.', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 15),
          pw.Text('V. Tangible/ Physical Projects (10 points) _______________________', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('• Computation is accumulated amount. Consumables not included. Office equipment/equipment for the CSC use alone are not credited.', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.Text('• Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, receipts and photo Documentation', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 6),
          _buildMappingPdfTable([
            ['2,000 and below', '1.0'], ['2,001 - 3,000', '1.5'],
            ['3,001 - 4,000', '2.0'], ['4,001 - 5,000', '2.5'],
            ['5,001 - 6,000', '3.0'], ['6,001 - 7,000', '3.5'],
            ['7,001 - 8,000', '4.0'], ['8,001 - 9,000', '4.5'],
            ['9,001 - 10,000', '5.0'], ['10,001 - 11,000', '5.5'],
            ['11,001 - 12,000', '6.0'], ['12,001 - 13,000', '6.5'],
            ['13,001 - 14,000', '7.0'], ['14,001 - 15,000', '7.5'],
          ], headerLabel: 'Amount (Php)'),
        ],
      ));

      // Page 3
      pdf.addPage(_buildPage(
        pageNumber: 3,
        theme: theme,
        logo: logo,
        isCampus: false,
        isSpecialized: true,
        councilLabel: councilLabel,
        content: [
          _buildMappingPdfTable([
            ['15,001 - 16,000', '8.0'], ['16,001 - 17,000', '8.5'],
            ['17,001 - 18,000', '9.0'], ['18,001 - 19,000', '9.5'],
            ['19,001 - above', '10.0'],
          ], headerLabel: 'Amount (Php)', currentScore: scores['v'] ?? 0, showScoreRow: true),
          pw.SizedBox(height: 15),
          pw.Text('VI. Fund Drive/ IGP (10 points) _______________________', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 3),
          pw.Text('Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 6),
          _buildMappingPdfTable([
            ['2,000 and below', '1.0'], ['2,001 - 3,000', '1.5'],
            ['3,001 - 4,000', '2.0'], ['4,001 - 5,000', '2.5'],
            ['5,001 - 6,000', '3.0'], ['6,001 - 7,000', '3.5'],
            ['7,001 - 8,000', '4.0'], ['8,001 - 9,000', '4.5'],
            ['9,001 - 10,000', '5.0'], ['10,001 - 11,000', '5.5'],
            ['11,001 - 12,000', '6.0'], ['12,001 - 13,000', '6.5'],
            ['13,001 - 14,000', '7.0'], ['14,001 - 15,000', '7.5'],
            ['15,001 - 16,000', '8.0'], ['16,001 - 17,000', '8.5'],
            ['17,001 - 18,000', '9.0'], ['18,001 - 19,000', '9.5'],
            ['19,001 - above', '10.0'],
          ], headerLabel: 'Amount (Php)', currentScore: scores['vi'] ?? 0, showScoreRow: true),
        ],
      ));

      // Page 4
      pdf.addPage(_buildPage(
        pageNumber: 4,
        theme: theme,
        logo: logo,
        isCampus: false,
        isSpecialized: true,
        councilLabel: councilLabel,
        content: [
          pw.Text('VII. Percentage of Implementation of the Approved Action Plan (10 points) _______________________', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 3),
          pw.Text('Supporting Documents: Copy of the approved Action Plan, Summary of Accomplishment Report', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 6),
          _buildPercentagePdfTable([
            ['94%-100%', '10'], ['88%-93%', '9'],
            ['82%-87%', '8'], ['76%-81%', '7'],
            ['70%-75%', '6'], ['64%-69%', '5'],
            ['58%-63%', '4'], ['52%-57%', '3'],
            ['46%-51%', '2'], ['40%-45%', '1'],
          ], currentScore: scores['vii'] ?? 0, showScoreRow: true),
          pw.SizedBox(height: 16),
          _buildSpecializedSummaryPdfTable(scores, grandTotal),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Grand Total: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text(grandTotal.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColor.fromHex('#4338CA'))),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('Certified True and Correct:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 35),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureCol('Signature over Printed name of Evaluator'),
              _signatureCol('Signature over Printed name of Evaluator'),
            ],
          ),
          pw.SizedBox(height: 35),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureCol('Signature over Printed name of Evaluator'),
              _signatureCol('Signature over Printed name of Evaluator'),
            ],
          ),
          pw.SizedBox(height: 40),
          pw.Text('Noted:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 20),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('LORAINE SUYU-TATTAO, Ph.D.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, decoration: pw.TextDecoration.underline)),
              pw.SizedBox(height: 2),
              pw.Text('University Director', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('Office of the Student Services and Welfare', style: pw.TextStyle(fontSize: 8)),
            ],
          ),
        ],
      ));

      return pdf;
    }

    // Standard 5-Page PDF Generation for College and Campus Student Councils
    pdf.addPage(_buildPage(
      pageNumber: 1,
      theme: theme,
      logo: logo,
      isCampus: isCampus,
      councilLabel: councilLabel,
      content: [
        _buildDocHeader('CRITERIA FOR THE SEARCH FOR OUTSTANDING $councilLabel SY $schoolYear'),
        pw.SizedBox(height: 15),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Organization: $orgName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text('Points: ${grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Campus: ${isCampus ? 'CENTRAL ADMINISTRATION' : 'LAL-LO CAMPUS'}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text('Adjectival Rating: ${adjectivalRating.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Center(child: pw.Text('ACTIVITIES CONDUCTED/ SPONSORED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, decoration: pw.TextDecoration.underline))),
        pw.SizedBox(height: 10),
        _buildPage1Matrix(scores, gridValues, isCampus),
        pw.SizedBox(height: 10),
        pw.Text('For Items III, IV, V and VI, the number of SDGs is no longer required, as discussed during the OSDW 3rd Quarter Meeting held last August 15, 2024. All activities under these items are now considered specific and aligned with their respective objectives.', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        _buildCategoricalPdfHeader(isCampus),
        _buildActivityCategoryPdfTable(
          title: 'III. Religious Activities (5 points)\nMax. No. of Activities: 5',
          docs: '• Approved Letter\n• Documentation\n• Narrative Report\n• Attendance Sheet (Except for Holy Mass and Praying of the Rosary)\n• Concept Paper',
          key: 'iii',
          gridValues: gridValues,
          maxActs: 5,
          isSDGMatrix: false,
          isCampus: isCampus,
        ),
      ],
    ));

    // Page 2
    pdf.addPage(_buildPage(
      pageNumber: 2,
      theme: theme,
      logo: logo,
      isCampus: isCampus,
      councilLabel: councilLabel,
      content: [
        _buildCategoricalPdfHeader(isCampus),
        _buildActivityCategoryPdfTable(
          title: 'IV. Socio-Cultural and Sports Activities (10 points)\nMax. No. of Activities: 5 for socio-cultural 5 for sports activities',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'iv',
          gridValues: gridValues,
          maxActs: 10,
          isSDGMatrix: false,
          isCampus: isCampus,
        ),
        pw.SizedBox(height: 10),
        _buildActivityCategoryPdfTable(
          title: 'V. Makakalikasan/ Clean and Green Activities and Projects (10 points)\nMax. No. of Activities: ${isCampus ? '5' : '10'}',
          docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU\n• Consent letter/Invitation Letter\n• Narrative report\n• Partner Certificate\n• Attendance Sheet\n• Documentation',
          key: 'v',
          gridValues: gridValues,
          maxActs: isCampus ? 5 : 10,
          isSDGMatrix: false,
          isCampus: isCampus,
        ),
        pw.SizedBox(height: 10),
        _buildActivityCategoryPdfTable(
          title: 'VI. Extension Services Sponsored/ Conducted (10 points)\nMax. No. of Activities: 5',
          docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU/ Barangay Resolution\n• Consent/Invitation Letter\n• Narrative report\n• Partner Certificate\n• Attendance Sheet\n• Documentation',
          key: 'vi',
          gridValues: gridValues,
          maxActs: 5,
          isSDGMatrix: false,
          isCampus: isCampus,
        ),
        pw.SizedBox(height: 8),
        pw.Text('For activities conducted with co-sponsor, the points will be divided equally. Any Regional Activity conducted should have CHED Endorsement.', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 15),
        pw.Text('VII. Tangible/ Physical Projects (15 points)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.Text('• Computation is accumulated amount. Consumables not included. Office equipment for CSC use alone not credited.', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 6),
        _buildMappingPdfTable([
          ['25,000 and below', '1.0'],
          ['25,001 - 30,000', '2.0'],
          ['30,001 - 35,000', '3.0'],
        ]),
      ],
    ));

    // Page 3
    pdf.addPage(_buildPage(
      pageNumber: 3,
      theme: theme,
      logo: logo,
      isCampus: isCampus,
      councilLabel: councilLabel,
      content: [
        _buildMappingPdfTable([
          ['35,001 - 40,000', '4.0'], ['40,001 - 45,000', '5.0'],
          ['45,001 - 50,000', '6.0'], ['50,001 - 55,000', '7.0'],
          ['55,001 - 60,000', '8.0'], ['60,001 - 65,000', '9.0'],
          ['65,001 - 70,000', '10.0'], ['70,001 - 75,000', '11.0'],
          ['75,001 - 80,000', '12.0'], ['80,001 - 85,000', '13.0'],
          ['85,001 - 90,000', '14.0'], ['90,001 - 95,000', '15.0'],
        ], title: 'VII. Tangible/ Physical Projects (Continued)', currentScore: scores['vii'] ?? 0, showScoreRow: true),
        pw.SizedBox(height: 15),
        pw.Text('VIII. Fund Drive/ IGP (10 points) _______________________', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.SizedBox(height: 3),
        pw.Text('Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 6),
        _buildMappingPdfTable([
          ['4,001 - 5,000', '1.0'], ['5,001 - 10,000', '1.5'],
          ['10,001 - 15,000', '2.0'], ['15,001 - 20,000', '2.5'],
          ['20,001 - 25,000', '3.0'], ['25,001 - 30,000', '3.5'],
          ['30,001 - 35,000', '4.0'], ['35,001 - 40,000', '4.5'],
          ['40,001 - 45,000', '5.0'], ['45,001 - 50,000', '5.5'],
          ['50,001 - 55,000', '6.0'], ['55,001 - 60,000', '6.5'],
          ['60,001 - 65,000', '7.0'], ['65,001 - 70,000', '7.5'],
          ['70,001 - 75,000', '8.0'], ['75,001 - 80,000', '8.5'],
        ], showScoreRow: false, currentScore: scores['viii'] ?? 0),
      ],
    ));

    // Page 4
    pdf.addPage(_buildPage(
      pageNumber: 4,
      theme: theme,
      logo: logo,
      isCampus: isCampus,
      councilLabel: councilLabel,
      content: [
        _buildMappingPdfTable([
          ['80,001 - 85,000', '9.0'],
          ['85,001 - 90,000', '9.5'],
          ['90,001 - 95,000', '10.0'],
        ], headerLabel: 'VIII. Fund Drive/ IGP (Continued)', currentScore: scores['viii'] ?? 0, showScoreRow: true),
        pw.SizedBox(height: 15),
        pw.Text('IX. Financial Assistance given to members (subsidy to activities and to seminar) (10 points) _______________________', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.SizedBox(height: 3),
        pw.Text('Supporting Documents: Disbursement Vouchers, Acknowledgment Receipt, Certificate of Appearance/Proof of Activity Conducted', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 6),
        _buildMappingPdfTable([
          ['4,001 - 5,000', '1.0'], ['5,001 - 10,000', '1.5'],
          ['10,001 - 15,000', '2.0'], ['15,001 - 20,000', '2.5'],
          ['20,001 - 25,000', '3.0'], ['25,001 - 30,000', '3.5'],
          ['30,001 - 35,000', '4.0'], ['35,001 - 40,000', '4.5'],
          ['40,001 - 45,000', '5.0'], ['45,001 - 50,000', '5.5'],
          ['50,001 - 55,000', '6.0'], ['55,001 - 60,000', '6.5'],
          ['60,001 - 65,000', '7.0'], ['65,001 - 70,000', '7.5'],
          ['70,001 - 75,000', '8.0'], ['75,001 - 80,000', '8.5'],
          ['80,001 - 85,000', '9.0'], ['85,001 - 90,000', '9.5'],
          ['90,001 - 95,000', '10.0'],
        ], currentScore: scores['ix'] ?? 0, showScoreRow: true),
        pw.SizedBox(height: 15),
        pw.Text('X. Percentage of Implementation of the Approved Action Plan (10 points) _______________________', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        pw.SizedBox(height: 3),
        pw.Text('Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 6),
        _buildPercentagePdfTable([
          ['94%-100%', '10'], ['88%-93%', '9'],
          ['82%-87%', '8'], ['76%-81%', '7'],
          ['70%-75%', '6'],
        ]),
      ],
    ));

    // Page 5
    pdf.addPage(_buildPage(
      pageNumber: 5,
      theme: theme,
      logo: logo,
      isCampus: isCampus,
      councilLabel: councilLabel,
      content: [
        _buildPercentagePdfTable([
          ['64%-69%', '5'], ['58%-63%', '4'],
          ['52%-57%', '3'], ['46%-51%', '2'],
          ['40%-45%', '1'],
        ], currentScore: scores['x'] ?? 0, showScoreRow: true),
        pw.SizedBox(height: 16),
        _buildSummaryPdfTable(scores, grandTotal),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Grand Total: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text(grandTotal.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColor.fromHex('#4338CA'))),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('Certified True and Correct:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 35),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _signatureCol('Signature over Printed name of Evaluator'),
            _signatureCol('Signature over Printed name of Evaluator'),
          ],
        ),
        pw.SizedBox(height: 35),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _signatureCol('Signature over Printed name of Evaluator'),
            _signatureCol('Signature over Printed name of Evaluator'),
          ],
        ),
        pw.SizedBox(height: 40),
        pw.Text('Noted:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 20),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('LORAINE SUYU-TATTAO, Ph.D.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, decoration: pw.TextDecoration.underline)),
            pw.SizedBox(height: 2),
            pw.Text('University Director', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text('Office of the Student Services and Welfare', style: pw.TextStyle(fontSize: 8)),
          ],
        ),
      ],
    ));

    return pdf;
  }

  static Future<void> saveAndDownloadPdf(
    BuildContext context, {
    required Map<String, dynamic> organization,
    required String schoolYear,
    required Map<String, double> scores,
    required Map<String, String> gridValues,
    required double grandTotal,
    required String adjectivalRating,
    String orgType = 'College Student Council',
  }) async {
    try {
      final orgName = organization['name']?.toString().toUpperCase().replaceAll(RegExp(r'[^\w\s-]'), '_') ?? 'ORGANIZATION';
      final fileName = '${orgName}_Evaluation_Sheet_SY_$schoolYear.pdf';

      final pdf = await generateEvaluationPdf(
        organization: organization,
        schoolYear: schoolYear,
        scores: scores,
        gridValues: gridValues,
        grandTotal: grandTotal,
        adjectivalRating: adjectivalRating,
        orgType: orgType,
      );
      final bytes = await pdf.save();

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Evaluation Sheet PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (outputFile != null) {
        if (!kIsWeb) {
          final file = File(outputFile);
          await file.writeAsBytes(bytes);
        }
        if (context.mounted) {
          AppUtils.showTopToast(context, 'PDF saved successfully!');
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppUtils.showTopToast(context, 'Error saving PDF: $e', isError: true);
      }
    }
  }

  static Future<void> showPdfPreviewDialog(
    BuildContext context, {
    required Map<String, dynamic> organization,
    required String schoolYear,
    required Map<String, double> scores,
    required Map<String, String> gridValues,
    required double grandTotal,
    required String adjectivalRating,
    String orgType = 'College Student Council',
  }) async {
    final folioFormat = PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch);
    final orgName = organization['name']?.toString().toUpperCase() ?? 'ORGANIZATION NAME';

    await showDialog(
      context: context,
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Container(
            width: screenSize.width * 0.96,
            height: screenSize.height * 0.94,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EVALUATION SHEET PRINT PREVIEW (FOLIO 8.5 x 13.0 in)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            await saveAndDownloadPdf(
                              context,
                              organization: organization,
                              schoolYear: schoolYear,
                              scores: scores,
                              gridValues: gridValues,
                              grandTotal: grandTotal,
                              adjectivalRating: adjectivalRating,
                              orgType: orgType,
                            );
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Save PDF File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: PdfPreview(
                    pdfFileName: '${orgName}_Evaluation_Sheet_SY_$schoolYear.pdf',
                    initialPageFormat: folioFormat,
                    pageFormats: {
                      'Folio / Long Paper (8.5 x 13.0 in)': folioFormat,
                    },
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    build: (format) async {
                      final pdf = await generateEvaluationPdf(
                        organization: organization,
                        schoolYear: schoolYear,
                        scores: scores,
                        gridValues: gridValues,
                        grandTotal: grandTotal,
                        adjectivalRating: adjectivalRating,
                        orgType: orgType,
                      );
                      return pdf.save();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static pw.Page _buildPage({
    required int pageNumber,
    required pw.ThemeData theme,
    required pw.ImageProvider? logo,
    required List<pw.Widget> content,
    bool isCampus = false,
    bool isSpecialized = false,
    String councilLabel = 'COLLEGE STUDENT COUNCIL',
  }) {
    final campusHeader = isSpecialized ? 'ANDREWS CAMPUS' : (isCampus ? 'Central Administration' : 'LAL-LO CAMPUS');
    final locationHeader = isSpecialized ? 'Caritan, Tuguegarao City, Cagayan' : (isCampus ? 'Caritan, Tuguegarao City, Cagayan' : 'Sta. Maria, Lal-lo, Cagayan');
    final emailHeader = isSpecialized ? 'osdw@csu.edu.ph' : (isCampus ? 'osdw@csu.edu.ph' : 'osdw.lallo@csu.edu.ph');
    final fbHeader = isSpecialized ? 'Ossw Andrews' : (isCampus ? 'CSU Office of Student Development & Welfare' : 'Osdw Lallo');
    final redColor = PdfColor.fromHex('#B71C1C');

    return pw.Page(
      pageFormat: PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch),
      theme: theme,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('REPUBLIC OF THE PHILIPPINES', style: pw.TextStyle(fontSize: 8, color: redColor)),
                      pw.Text('CAGAYAN STATE UNIVERSITY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: redColor)),
                      pw.Text(campusHeader, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: redColor)),
                      pw.Text(locationHeader, style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic)),
                    ],
                  ),
                ),
                pw.Container(
                  width: 65,
                  child: pw.Center(
                    child: logo != null ? pw.Container(height: 55, width: 55, child: pw.Image(logo)) : pw.SizedBox(width: 55, height: 55),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Email Address: $emailHeader', style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic, decoration: pw.TextDecoration.underline)),
                      pw.Text('Website: www.csu.edu.ph', style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic, decoration: pw.TextDecoration.underline)),
                      pw.Text('Facebook Page: $fbHeader', style: pw.TextStyle(fontSize: 8, color: redColor, fontStyle: pw.FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Text('OFFICE OF STUDENT DEVELOPMENT AND WELFARE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1.5, color: PdfColors.black),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: content,
              ),
            ),
            pw.Divider(thickness: 0.8, color: PdfColors.black),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text('$pageNumber | P a g e  ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text('Search for the Most Outstanding $councilLabel Organization SY 2025-2026', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        );
      },
    );
  }

  static pw.Widget _buildDocHeader(String title) {
    return pw.Center(
      child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
    );
  }

  static pw.Widget _buildSpecializedPage1Matrix(Map<String, double> scores, Map<String, String> gridValues) {
    return pw.Column(
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
            2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
            4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
            6: pw.FlexColumnWidth(1), 7: pw.FlexColumnWidth(1),
          },
          children: [
            _buildMatrixIAndIIHeaderPdf(false),
            _sdgRow(['3', '5.5'], ['3', '5'], ['5', '4.5'], ['5', '4'], ['7', '3.5'], ['10', '3']),
            _sdgRow(['2', '5'], ['2', '4.5'], ['4', '4'], ['4', '3.5'], ['6', '3'], ['9', '2.5']),
            _sdgRow(['1', '4.5'], ['1', '4'], ['3', '3.5'], ['3', '3'], ['5', '2.5'], ['8', '2']),
            pw.TableRow(children: [
              pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text('Attendance should be 50%+1 of the total target participants.', style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic))),
              for (var i = 0; i < 7; i++) pw.SizedBox(),
            ]),
          ],
        ),
        _buildActivityCategoryPdfTable(
          title: 'I. Symposium /Seminars Conducted (20 points)\nMax. No. of Activities: 7',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'i',
          gridValues: gridValues,
          maxActs: 7,
          isSDGMatrix: true,
        ),
        _buildActivityCategoryPdfTable(
          title: 'II. Activities Conducted /Sponsored in line with the nature of the organization (30 points)\nMax. No. of Activities: 10',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'ii',
          gridValues: gridValues,
          maxActs: 10,
          isSDGMatrix: true,
        ),
      ],
    );
  }

  static pw.Widget _buildPage1Matrix(Map<String, double> scores, Map<String, String> gridValues, bool isCampus) {
    final Map<int, pw.TableColumnWidth> cols = isCampus ? const {
      0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
      2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(1),
    } : const {
      0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
      2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(1), 7: pw.FlexColumnWidth(1),
    };

    return pw.Column(
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          columnWidths: cols,
          children: [
            _buildMatrixIAndIIHeaderPdf(isCampus),
            if (isCampus) ...[
              _sdgRow(['3', '1.5'], ['5', '2.5'], ['5', '2'], ['5', '1.5'], ['7', '2.5']),
              _sdgRow(['2', '1'], ['4', '2'], ['4', '1.5'], ['4', '1'], ['6', '2']),
              _sdgRow(['1', '.5'], ['3', '1.5'], ['3', '1'], ['3', '.5'], ['5', '1.5']),
              pw.TableRow(children: [
                pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text('Attendance should be 50%+1 of the total target participants.', style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic))),
                pw.SizedBox(),
                pw.SizedBox(),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('2  ', style: const pw.TextStyle(fontSize: 6)),
                      pw.Text('1', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
              ]),
              pw.TableRow(children: [
                pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('1  ', style: const pw.TextStyle(fontSize: 6)),
                      pw.Text('.5', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
              ]),
            ] else ...[
              _sdgRow(['3', '2.5'], ['3', '2.5'], ['5', '2.5'], ['5', '2'], ['5', '1.5'], ['7', '2.5']),
              _sdgRow(['2', '2'], ['2', '2'], ['4', '2'], ['4', '1.5'], ['4', '1'], ['6', '2']),
              _sdgRow(['1', '1.5'], ['1', '1.5'], ['3', '1.5'], ['3', '1'], ['3', '.5'], ['5', '1.5']),
              pw.TableRow(children: [
                pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text('Attendance should be 50%+1 of the total target participants.', style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic))),
                for (var i = 0; i < 7; i++) pw.SizedBox(),
              ]),
            ],
          ],
        ),
        _buildActivityCategoryPdfTable(
          title: 'I. Symposium/ Seminars Conducted (10 points)\nMax. No. of Activities: 4',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'i',
          gridValues: gridValues,
          maxActs: 4,
          isSDGMatrix: true,
          isCampus: isCampus,
        ),
        _buildActivityCategoryPdfTable(
          title: 'II. Convocations/ Programs and Literary Activities (10 points)\nMax. No. of Activities: 4',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'ii',
          gridValues: gridValues,
          maxActs: 4,
          isSDGMatrix: true,
          isCampus: isCampus,
        ),
      ],
    );
  }

  static pw.TableRow _buildMatrixIAndIIHeaderPdf(bool isCampus) {
    final levels = isCampus ? [
      'Int\'l Level\n(at least 3 countries)',
      'National Level',
      'Regional Level/\nProvincial',
      'University Wide/\nMunicipality',
      'Campus Wide/\nBarangay'
    ] : [
      'Int\'l Level\n(at least 3 countries)',
      'National Level',
      'Regional Level/\nProvincial',
      'University Wide/\nMunicipality',
      'Campus Wide/\nBarangay',
      'College Level'
    ];

    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _cell('Activities', bold: true),
        _cell('Supporting Documents', bold: true),
        for (final l in levels)
          pw.Container(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Column(
              children: [
                pw.Text(l, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 2),
                pw.Divider(thickness: 0.5, color: PdfColors.black),
                pw.SizedBox(height: 2),
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Center(child: pw.Text('SDGs', style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold)))),
                    pw.Container(width: 0.5, height: 8, color: PdfColors.black),
                    pw.Expanded(child: pw.Center(child: pw.Text('Pts', style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold)))),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _buildCategoricalPdfHeader(bool isCampus) {
    final Map<int, pw.TableColumnWidth> cols = isCampus ? const {
      0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
      2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(1),
    } : const {
      0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
      2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(1), 7: pw.FlexColumnWidth(1),
    };

    final headers = isCampus ? [
      _ptsHeader('International Level\n(at least 3 countries)\n3 points'),
      _ptsHeader('National Level\n2.5 points'),
      _ptsHeader('Regional Level/\nProvincial\n2 points'),
      _ptsHeader('University Wide/\nMunicipality\n1.5 points'),
      _ptsHeader('Campus Wide/\nBarangay\n1 point'),
    ] : [
      _ptsHeader('International Level\n(at least 3 countries)\n3.5 points'),
      _ptsHeader('National Level\n3 points'),
      _ptsHeader('Regional Level/\nProvincial\n2.5 points'),
      _ptsHeader('University Wide/\nMunicipality\n2 points'),
      _ptsHeader('Campus Wide/\nBarangay\n1.5 points'),
      _ptsHeader('College Level\n1 point'),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: cols,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('Activities', bold: true),
            _cell('Supporting Documents', bold: true),
            ...headers,
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildActivityCategoryPdfTable({
    required String title,
    required String docs,
    required String key,
    required Map<String, String> gridValues,
    required int maxActs,
    required bool isSDGMatrix,
    bool isCampus = false,
  }) {
    final levels = isCampus ? ['intl', 'natl', 'regl', 'univ', 'camp'] : ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    final double rowHeight = maxActs > 5 ? 12.0 : 16.0;

    final Map<int, pw.TableColumnWidth> cols = isCampus ? const {
      0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
      2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(1),
    } : const {
      0: pw.FixedColumnWidth(125), 1: pw.FixedColumnWidth(125),
      2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
      4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1),
      6: pw.FlexColumnWidth(1), 7: pw.FlexColumnWidth(1),
    };

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: cols,
      children: [
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(title, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(docs, style: const pw.TextStyle(fontSize: 6.0)),
            ),
            for (final lvl in levels)
              pw.Table(
                columnWidths: const {0: pw.FlexColumnWidth(1)},
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
                ),
                children: List.generate(maxActs, (idx) {
                  final act = idx + 1;
                  return pw.TableRow(
                    children: [
                      pw.Container(
                        height: rowHeight,
                        alignment: pw.Alignment.center,
                        child: isSDGMatrix
                            ? _sdgAndPtsPdfCell(key, act, lvl, gridValues)
                            : _ptsOnlyPdfCell(key, act, lvl, gridValues),
                      ),
                    ],
                  );
                }),
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _sdgAndPtsPdfCell(String key, int act, String lvl, Map<String, String> gridValues) {
    final sdgVal = gridValues['${key}_${act}_${lvl}_sdg'] ?? '';
    final ptsVal = gridValues['${key}_${act}_${lvl}_pts'] ?? '';
    final hasSDG = sdgVal.isNotEmpty && sdgVal != '—';
    final hasPts = ptsVal.isNotEmpty && ptsVal != '—';

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          children: [
            pw.Center(
              child: pw.Text(
                hasSDG ? sdgVal : '—',
                style: pw.TextStyle(
                  fontSize: 5.5,
                  fontWeight: hasSDG ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                hasPts ? ptsVal : '—',
                style: pw.TextStyle(
                  fontSize: 5.5,
                  fontWeight: hasPts ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: hasPts ? PdfColor.fromHex('#4338CA') : PdfColors.black,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _ptsOnlyPdfCell(String key, int act, String lvl, Map<String, String> gridValues) {
    final ptsVal = gridValues['${key}_${act}_$lvl'] ?? gridValues['${key}_${act}_${lvl}_pts'] ?? '';
    final hasPts = ptsVal.isNotEmpty && ptsVal != '—';

    return pw.Center(
      child: pw.Text(
        hasPts ? ptsVal : '—',
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: hasPts ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: hasPts ? PdfColor.fromHex('#4338CA') : PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _buildMappingPdfTable(List<List<String>> rows, {String headerLabel = 'Amount', String? title, double currentScore = 0, bool showScoreRow = false, bool showHeader = true}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FixedColumnWidth(80)},
      children: [
        if (showHeader)
          if (title != null)
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(title, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('Points', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
              ],
            )
          else
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(headerLabel, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('Points', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
              ],
            ),
        ...rows.map((r) => pw.TableRow(children: [
          pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text(r[0], style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center)),
          pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text(r[1], style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
        ])),
        if (showScoreRow)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EEF2FF')),
            children: [
              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('Actual Score achieved based on rubric:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(currentScore.toStringAsFixed(1), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#4338CA')), textAlign: pw.TextAlign.center)),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildPercentagePdfTable(List<List<String>> rows, {String headerLabel = 'Percentage of Implementation', double currentScore = 0, bool showScoreRow = false}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FixedColumnWidth(80)},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(headerLabel, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
            pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('Points', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
          ],
        ),
        ...rows.map((r) => pw.TableRow(children: [
          pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text(r[0], style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center)),
          pw.Container(padding: const pw.EdgeInsets.all(3), child: pw.Text(r[1], style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
        ])),
        if (showScoreRow)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EEF2FF')),
            children: [
              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('Actual Score achieved based on rubric:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(currentScore.toStringAsFixed(1), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#4338CA')), textAlign: pw.TextAlign.center)),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildSpecializedSummaryPdfTable(Map<String, double> scores, double grandTotal) {
    final subCats = [
      ['I. Symposium/ Seminars Conducted (20 points)', scores['i'] ?? 0],
      ['II. Activities Conducted/ Sponsored in line with the nature of the organization (30 points)', scores['ii'] ?? 0],
      ['III. Maka-kalikasan/ Clean and Green Activities and Projects (10 points)', scores['iii'] ?? 0],
      ['IV. Extension Services Sponsored/Conducted (10 points)', scores['iv'] ?? 0],
      ['V. Tangible/ Physical Projects (10 points)', scores['v'] ?? 0],
      ['VI. Fund Drive/ IGP (10 points)', scores['vi'] ?? 0],
      ['VII. Percentage of Implementation of the Approved Action Plan (10 points)', scores['vii'] ?? 0],
    ];

    return pw.Column(
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FixedColumnWidth(80)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sub Categories', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text('Score', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
              ],
            ),
            ...subCats.map((sc) => pw.TableRow(children: [
              pw.Container(padding: const pw.EdgeInsets.all(5), child: pw.Text(sc[0].toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Container(padding: const pw.EdgeInsets.all(5), child: pw.Text((sc[1] as double).toStringAsFixed(1), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
            ])),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryPdfTable(Map<String, double> scores, double grandTotal) {
    final subCats = [
      ['I. Symposium/ Seminars Conducted (10 points)', scores['i'] ?? 0],
      ['II. Convocations/Programs and Literary Activities (10 points)', scores['ii'] ?? 0],
      ['III. Religious Activities (5 points)', scores['iii'] ?? 0],
      ['IV. Socio-Cultural & Sports Activities (10 points)', scores['iv'] ?? 0],
      ['V. Maka-kalikasan/Clean and Green Activities and Projects (10 points)', scores['v'] ?? 0],
      ['VI. Extension Services Sponsored/Conducted (10 points)', scores['vi'] ?? 0],
      ['VII. Tangible/ Physical Projects (15 points)', scores['vii'] ?? 0],
      ['VIII. Fund Drive/ IGP (10 points)', scores['viii'] ?? 0],
      ['IX. Financial Assistance given to members (10 points)', scores['ix'] ?? 0],
      ['X. Percentage of Implementation of the Approved Action Plan (10 points)', scores['x'] ?? 0],
    ];

    return pw.Column(
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FixedColumnWidth(80)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sub Categories', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text('Score', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
              ],
            ),
            ...subCats.map((sc) => pw.TableRow(children: [
              pw.Container(padding: const pw.EdgeInsets.all(5), child: pw.Text(sc[0].toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Container(padding: const pw.EdgeInsets.all(5), child: pw.Text((sc[1] as double).toStringAsFixed(1), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
            ])),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 7, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _ptsHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
    );
  }

  static pw.TableRow _sdgRow(List<String> p1, List<String> p2, List<String> p3, List<String> p4, List<String> p5, [List<String>? p6]) {
    final pairs = [p1, p2, p3, p4, p5];
    if (p6 != null) pairs.add(p6);

    return pw.TableRow(
      children: [
        pw.SizedBox(), pw.SizedBox(),
        for (final pair in pairs)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Center(child: pw.Text(pair[0], style: const pw.TextStyle(fontSize: 6)))),
                pw.Container(width: 0.5, height: 10, color: PdfColors.grey400),
                pw.Expanded(child: pw.Center(child: pw.Text(pair[1], style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)))),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _signatureCol(String label) {
    return pw.Column(
      children: [
        pw.Container(width: 180, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
        pw.SizedBox(height: 3),
        pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
      ],
    );
  }
}
