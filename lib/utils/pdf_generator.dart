  import 'dart:io';
  import 'package:file_picker/file_picker.dart';
  import 'package:flutter/foundation.dart';
  import 'package:flutter/material.dart';
  import 'package:pdf/pdf.dart';
  import 'package:pdf/widgets.dart' as pw;
  import 'package:printing/printing.dart';
  import 'package:csuatlasf/utils/app_utils.dart';
  import 'package:flutter/services.dart' show rootBundle;
  import 'package:csuatlasf/widgets/csc_scoring_components.dart';

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

    /// Set by the edit dialog right before the preview opens.
    static Map<String, String> customSignatories = {};

    /// Default names/positions for the four signatories.
    static Map<String, String> signatoryDefaults({Map<String, dynamic>? president, Map<String, dynamic>? adviser}) => {
      'prepared_name': (president?['full_name'] ?? '(Name of Student)').toString(),
      'prepared_title': 'President',
      'attested_name': (adviser?['full_name'] ?? '(Adviser)').toString(),
      'attested_title': 'Adviser',
      'noted_name': 'Donna Macadangdang',
      'noted_title': 'OSDW Coordinator',
      'approved_name': 'Engr. James B. Cabildo',
      'approved_title': 'CEO, Lal-lo Campus',
    };

    static Future<pw.Document> generateGPOADocument({
      required Map<String, dynamic> organization,
      required List<Map<String, dynamic>> activities,
      required Map<String, dynamic>? president,
      required Map<String, dynamic>? adviser,
      PdfPageFormat? format,
    }) async {
      final pageFormat = format ??
          PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch).landscape;
      final pdf = pw.Document();

      // Times-style serif (swap the paths in _FormFonts.load() to times*.ttf for real Times New Roman)
      final ff = await _FormFonts.load();
      final theme = pw.ThemeData.withFont(
        base: ff.serif,
        bold: ff.serifBold,
        italic: ff.serifItalic,
      );

      // Signatories: defaults, overridden by anything typed in the edit dialog
      final sig = signatoryDefaults(president: president, adviser: adviser);
      final custom = organization['gpoa_signatories'];
      if (custom is Map) {
        custom.forEach((k, v) {
          final t = v?.toString().trim() ?? '';
          if (t.isNotEmpty) sig[k.toString()] = t;
        });
      }

      customSignatories.forEach((k, v) {
        final t = v.trim();
        if (t.isNotEmpty) sig[k] = t;
      });

      pw.ImageProvider? logo, iso, pilipinasImage, stars, aun, bldg;

      try { logo = await imageFromAssetBundle('assets/images/csulogo.png'); } catch (_) {}
      try { iso = await imageFromAssetBundle('assets/images/iso_pab.png'); } catch (_) {}
      try { pilipinasImage = await imageFromAssetBundle('assets/images/bagong_pilipinas.png'); } catch (_) {}
      try { stars = await imageFromAssetBundle('assets/images/qs_stars.png'); } catch (_) {}
      try { aun = await imageFromAssetBundle('assets/images/aun_qa.png'); } catch (_) {}
      try { bldg = await imageFromAssetBundle('assets/images/vision_mission_building.png'); } catch (_) {}

      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
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
            final fbHeader = isSpecialized ? 'OSDW Andrews' : (isCampus ? 'CSU Office of Student Development & Welfare' : 'Osdw Lallo');

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
                  _signatureUnit('Prepared by:', sig['prepared_name']!, sig['prepared_title']!),
                  _signatureUnit('Attested by:', sig['attested_name']!, sig['attested_title']!),
                  _signatureUnit('Noted by:', sig['noted_name']!, sig['noted_title']!),
                  _signatureUnit('Approved by:', sig['approved_name']!, sig['approved_title']!),
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

  class _FormFonts {
    final pw.Font sans, sansBold, sansItalic, sansBoldItalic, serif, serifBold, serifItalic;
    const _FormFonts({
      required this.sans, required this.sansBold, required this.sansItalic, required this.sansBoldItalic,
      required this.serif, required this.serifBold, required this.serifItalic,
    });

    static Future<_FormFonts> load() async {
      Future<pw.Font> a(String path) async {
        final data = await rootBundle.load(path);
        return pw.Font.ttf(data);
      }
      return _FormFonts(
        sans: await a('assets/fonts/FormSans-Regular.ttf'),
        sansBold: await a('assets/fonts/FormSans-Bold.ttf'),
        sansItalic: await a('assets/fonts/FormSans-Italic.ttf'),
        sansBoldItalic: await a('assets/fonts/FormSans-BoldItalic.ttf'),
        serif: await a('assets/fonts/FormSerif-Regular.ttf'),
        serifBold: await a('assets/fonts/FormSerif-Bold.ttf'),
        serifItalic: await a('assets/fonts/FormSerif-Italic.ttf'),
      );
    }
  }

  class _Cell {
    final int? sdg;
    final double? pts;
    const _Cell(this.sdg, this.pts);
  }
  
  class _CatDef {
    final String key, title, docs, short;
    final int maxActs;
    final bool sdg;
    final double maxPoints;
    const _CatDef(this.key, this.title, this.docs, this.short, this.maxActs, this.sdg, this.maxPoints);
  }
  
  class CSCEvaluationPdfGenerator {
    static final PdfColor _ink = PdfColor.fromHex('#000000');
    static final PdfColor _hit = PdfColor.fromHex('#EEF2FF');
  
    // ---------------------------------------------------------------------
    // Official "No. of SDGs -> Pts" tables.  [minSdgs, points] per level,
    // highest tier first.  Level order: intl, natl, regl, univ, camp, coll
    // ---------------------------------------------------------------------
    static const _tiers = kSdgTiers;
    static _FormFonts? _ff;
    static const double _wA = 112, _wB = 103; // Activities / Supporting Documents widths
    static const _bs = pw.BorderSide(width: 0.5);

    static pw.TextStyle _sans(double size, {bool bold = false, bool italic = false, PdfColor? color}) {
      final f = _ff!;
      return pw.TextStyle(
        font: bold ? (italic ? f.sansBoldItalic : f.sansBold) : (italic ? f.sansItalic : f.sans),
        fontSize: size,
        color: color,
      );
    }

    static pw.TextStyle _serif(double size,
        {bool bold = false, bool italic = false, PdfColor? color, bool underline = false}) {
      final f = _ff!;
      return pw.TextStyle(
        font: bold ? f.serifBold : (italic ? f.serifItalic : f.serif),
        fontSize: size,
        color: color,
        decoration: underline ? pw.TextDecoration.underline : null,
      );
    }

    static pw.Widget _box({required pw.Widget child, double? width, double? height,
      pw.EdgeInsets pad = pw.EdgeInsets.zero}) =>
        pw.Container(
          width: width, height: height, padding: pad, alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(border: pw.Border(right: _bs, bottom: _bs)),
          child: child,
        );
  
    static const List<String> _levelKeys = ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    static const List<String> _levelPtsSpecCollege = ['3.5 points', '3 points', '2.5 points', '2 points', '1.5 points', '1 point'];
    static const List<String> _levelPtsCampus = ['3 points', '2.5 points', '2 points', '1.5 points', '1 point'];

  
    // ---------------------------------------------------------------------
    // Amount -> points tables (exactly as on the official forms)
    // ---------------------------------------------------------------------
    /// Specialized: Tangible (V) and Fund Drive (VI)
    static const List<List<String>> _standardAmountRows = [
      ['2,000 and below', '1.0'], ['2,001 – 3,000', '1.5'], ['3,001 – 4,000', '2.0'],
      ['4,001 – 5,000', '2.5'], ['5,001 – 6,000', '3.0'], ['6,001 – 7,000', '3.5'],
      ['7,001 – 8,000', '4.0'], ['8,001 – 9,000', '4.5'], ['9,001 – 10,000', '5.0'],
      ['10,001 – 11,000', '5.5'], ['11,001 – 12,000', '6.0'], ['12,001 – 13,000', '6.5'],
      ['13,001 – 14,000', '7.0'], ['14,001 – 15,000', '7.5'], ['15,001 – 16,000', '8.0'],
      ['16,001 – 17,000', '8.5'], ['17,001 – 18,000', '9.0'], ['18,001 – 19,000', '9.5'],
      ['19,001 – above', '10.0'],
    ];
  
    /// Campus / College: Tangible (VII)
    static const List<List<String>> _tangibleFirst = [
      ['25,000 and below', '1.0'], ['25,001 – 30,000', '2.0'], ['30,001 – 35,000', '3.0'],
    ];
    static const List<List<String>> _tangibleCont = [
      ['35,001 – 40,000', '4.0'], ['40,001 – 45,000', '5.0'], ['45,001 – 50,000', '6.0'],
      ['50,001 – 55,000', '7.0'], ['55,001 – 60,000', '8.0'], ['60,001 – 65,000', '9.0'],
      ['65,001 – 70,000', '10.0'], ['70,001 – 75,000', '11.0'], ['75,001 – 80,000', '12.0'],
      ['80,001 – 85,000', '13.0'],['85,001 – 90,000', '14.0'], ['90,001 – above', '15.0'],
    ];
  
    /// Campus: Fund Drive (VIII) and Financial Assistance (IX)
    static const List<List<String>> _campusAmountRows = [
      ['4,001 – 5,000', '1.0'], ['5,001 – 10,000', '1.5'], ['10,001 – 15,000', '2.0'],
      ['15,001 – 20,000', '2.5'], ['20,001 – 25,000', '3.0'], ['25,001 – 30,000', '3.5'],
      ['30,001 – 35,000', '4.0'], ['35,001 – 40,000', '4.5'], ['40,001 – 45,000', '5.0'],
      ['45,001 – 50,000', '5.5'], ['50,001 – 55,000', '6.0'], ['55,001 – 60,000', '6.5'],
      ['60,001 – 65,000', '7.0'], ['65,001 – 70,000', '7.5'], ['70,001 – 75,000', '8.0'],
      ['75,001 – 80,000', '8.5'], ['80,001 – 85,000', '9.0'], ['85,001 – 90,000', '9.5'],
      ['90,001 – above', '10.0'],
    ];
  
    /// College: Fund Drive (VIII)
    static const List<List<String>> _collegeFundRows = [
      ['4,001 – 5,000', '1.0'], ['5,001 – 10,000', '2.0'], ['10,001 – 15,000', '3.0'],
      ['15,001 – 20,000', '4.0'], ['20,001 – 25,000', '5.0'], ['25,001 – 30,000', '6.0'],
      ['30,001 – 35,000', '7.0'], ['35,001 – 40,000', '8.0'], ['40,001 – 45,000', '9.0'],
      ['45,001 – above', '10.0'],
    ];
  
    /// College: Financial Assistance (IX)
    static const List<List<String>> _collegeFinRows = [
      ['5,000 and below', '1.0'], ['5,001 – 10,000', '2.0'], ['10,001 – 15,000', '3.0'],
      ['15,001 – 20,000', '4.0'], ['20,001 – 25,000', '5.0'], ['25,001 – 30,000', '6.0'],
      ['30,001 – 35,000', '7.0'], ['35,001 – 40,000', '8.0'], ['40,001 – 45,000', '9.0'],
      ['45,001 – above', '10.0'],
    ];
  
    /// Percentage of implementation (all org types)
    static const List<List<String>> _percentRows = [
      ['94%-100%', '10'], ['88%-93%', '9'], ['82%-87%', '8'], ['76%-81%', '7'], ['70%-75%', '6'],
      ['64%-69%', '5'], ['58%-63%', '4'], ['52%-57%', '3'], ['46%-51%', '2'], ['40%-45%', '1'],
    ];
  
    // ---------------------------------------------------------------------
    // Supporting documents text
    // ---------------------------------------------------------------------
    static const String _docsSeminar =
        '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper';
    static const String _docsReligious =
        '• Approved Letter\n• Documentation\n• Narrative Report\n• Attendance Sheet (Except for Holy Mass and Praying of the Rosary)\n• Concept Paper';
    static const String _docsGreen =
        '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU\n• Consent letter/Invitation Letter\n• Narrative report\n• Certificate signed by the partner agency/ organization/ institution\n• Attendance Sheet\n• Documentation';
    static const String _docsExtension =
        '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU/ Resolution from the barangay/ Excerpts from the minutes of the meeting\n• Consent letter/Invitation Letter\n• Narrative report\n• Certificate signed by the partner agency/ organization/ institution\n• Attendance Sheet\n• Documentation';
  
    static List<_CatDef> _categories(String p) {
      if (p == 'spec') {
        return const [
          _CatDef('i', 'I. Symposium/ Seminars Conducted (20 points)\nMax. No. of Activities: 7', _docsSeminar, 'I. Symposium/ Seminars', 7, true, 20),
          _CatDef('ii', 'II. Activities Conducted/ Sponsored in line with the nature of the organization (30 points)\nMax. No. of Activities: 10', _docsSeminar, 'II. Activities (nature of org.)', 10, true, 30),
          _CatDef('iii', 'III. Makakalikasan/ Clean and Green Activities and Projects (10 points)\nMax. No. of Activities: 10', _docsGreen, 'III. Clean and Green', 10, false, 10),
          _CatDef('iv', 'IV. Extension Services Sponsored/ Conducted (10 points)\nMax. No. of Activities: 5', _docsExtension, 'IV. Extension Services', 5, false, 10),
        ];
      }
      return [
        const _CatDef('i', 'I. Symposium/ Seminars Conducted (10 points)\nMax. No. of Activities: 4', _docsSeminar, 'I. Symposium/ Seminars', 4, true, 10),
        const _CatDef('ii', 'II. Convocations/ Programs and Literary Activities (10 points)\nMax. No. of Activities: 4', _docsSeminar, 'II. Convocations/ Literary', 4, true, 10),
        const _CatDef('iii', 'III. Religious Activities (5 points)\nMax. No. of Activities: 5', _docsReligious, 'III. Religious', 5, false, 5),
        const _CatDef('iv', 'IV. Socio-Cultural and Sports Activities (10 points)\nMax. No. of Activities: 5 for socio-cultural 5 for sports activities', _docsSeminar, 'IV. Socio-Cultural & Sports', 10, false, 10),
        _CatDef('v', 'V. Makakalikasan/ Clean and Green Activities and Projects (10 points)\nMax. No. of Activities: ${p == 'campus' ? 5 : 10}', _docsGreen, 'V. Clean and Green', p == 'campus' ? 5 : 10, false, 10),
        const _CatDef('vi', 'VI. Extension Services Sponsored/ Conducted (10 points)\nMax. No. of Activities: 5', _docsExtension, 'VI. Extension Services', 5, false, 10),
      ];
    }
  
    // ---------------------------------------------------------------------
    // Helpers: levels, columns, value lookup, totals
    // ---------------------------------------------------------------------
    static List<String> _levels(String profile) => _levelKeys.sublist(0, profile == 'campus' ? 5 : 6);
  
    static Map<int, pw.TableColumnWidth> _cols(String profile) {
      final n = _levels(profile).length;
      return <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(_wA),
        1: const pw.FixedColumnWidth(_wB),
        for (var i = 0; i < n; i++) i + 2: const pw.FlexColumnWidth(1),
      };
    }
  
    static String _fmt(double v) => v.toStringAsFixed(1);
  
    /// Points for a number of SDGs at a level (official table). 0 if below the lowest tier.
    static double? _ptsFromSdg(String profile, String lvl, int sdg) {
      final tiers = _tiers[profile];
      final idx = _levelKeys.indexOf(lvl);
      if (tiers == null || idx < 0 || idx >= tiers.length) return null;
      for (final t in tiers[idx]) {
        if (sdg >= t[0]) return t[1].toDouble();
      }
      return 0.0;
    }
  
    static _Cell _sdgCell(String profile, String key, int act, String lvl, Map<String, String> g) {
      final sdg = int.tryParse((g['${key}_${act}_${lvl}_sdg'] ?? '').trim());
      var pts = double.tryParse((g['${key}_${act}_${lvl}_pts'] ?? '').trim());
      if (pts == null && sdg != null && sdg > 0) pts = _ptsFromSdg(profile, lvl, sdg);
      return _Cell(sdg, pts);
    }

    static double? _ptsOnly(String key, int act, String lvl, Map<String, String> g, [String? orgType]) {
      final a = (g['${key}_${act}_$lvl'] ?? '').trim();
      final b = (g['${key}_${act}_${lvl}_pts'] ?? '').trim();
      final v = double.tryParse(a.isNotEmpty ? a : b);
      if (v == null) return null;
      return clampLevelPts(lvl, v, orgType);
    }
  
    static double _levelTotal(String profile, _CatDef c, String lvl, Map<String, String> g) {
      var sum = 0.0;
      for (var a = 1; a <= c.maxActs; a++) {
        final v = c.sdg
            ? _sdgCell(profile, c.key, a, lvl, g).pts
            : _ptsOnly(c.key, a, lvl, g, profile == 'spec' ? 'specialized' : profile);
        if (v != null) sum += v;
      }
      return sum;
    }
  

    // =====================================================================
    // MAIN GENERATOR
    // =====================================================================
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
      final ff = await _FormFonts.load();
      _ff = ff;
      final theme = pw.ThemeData.withFont(
          base: ff.sans, bold: ff.sansBold, italic: ff.sansItalic, boldItalic: ff.sansBoldItalic);
  
      pw.ImageProvider? logo;
      try { logo = await imageFromAssetBundle('assets/images/csulogo.png'); } catch (_) {}
  
      final typeLower = orgType.toLowerCase();
      final isCampus = typeLower.contains('campus');
      final isSpecialized = typeLower.contains('specialized') || typeLower.contains('special');
      final profile = isSpecialized ? 'spec' : (isCampus ? 'campus' : 'college');
  
      final councilLabel = isSpecialized ? 'SPECIALIZED ORGANIZATION' : (isCampus ? 'CAMPUS STUDENT COUNCIL' : 'COLLEGE STUDENT COUNCIL');
      final footerLabel = isSpecialized
          ? 'Specialized Organization'
          : (isCampus ? 'Campus Student Council Organization' : 'College Student Council Organization');
      final campusLine = isSpecialized ? 'ANDREWS CAMPUS' : (isCampus ? 'CENTRAL ADMINISTRATION' : 'LAL-LO CAMPUS');
      final orgName = organization['name']?.toString().toUpperCase() ?? 'ORGANIZATION NAME';
  
      final cats = _categories(profile);
      _CatDef def(String k) => cats.firstWhere((c) => c.key == k);
      pw.Widget cat(String k) => _buildActivityCategoryPdfTable(
          profile: profile, def: def(k), gridValues: gridValues, score: scores[k] ?? 0);
  
      void addPage(int n, List<pw.Widget> content) => pdf.addPage(_buildPage(
          pageNumber: n, theme: theme, logo: logo, isCampus: isCampus, isSpecialized: isSpecialized,
          footerLabel: footerLabel, schoolYear: schoolYear, content: content));

      pw.Widget scoredHeading(String t, String key) {
        final s = scores[key] ?? 0;
        return pw.RichText(
          text: pw.TextSpan(
            style: _sans(10, bold: true, color: PdfColors.black),
            children: [
              pw.TextSpan(text: '$t ', style: _sans(10, bold: true, color: PdfColors.black)),
              pw.TextSpan(
                text: _fmt(s),
                style: _sans(10, bold: true, color: PdfColors.black)
                    .copyWith(decoration: pw.TextDecoration.underline),
              ),
            ],
          ),
        );
      }
      pw.Widget note(String t) => pw.Text(t, style: _sans(7.5, italic: true));
      pw.Widget bullet(String t) => pw.Text('• $t', style: _sans(7.5, italic: true));
      pw.Widget amt(List<List<String>> rows, {String? key, String label = 'Amount', bool header = true}) =>
          _buildMappingPdfTable(rows, headerLabel: label, currentScore: key == null ? 0 : (scores[key] ?? 0), showHeader: header);
      pw.Widget pct(List<List<String>> rows, String key, {bool header = true}) =>
          _buildPercentageList(rows, currentScore: scores[key] ?? 0, showHeader: header);
  
      const fundDocs =
          'Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation';
      const finDocs =
          'Supporting Documents: Disbursement Vouchers, Acknowledgment Receipt, Certificate of Appearance/Proof of Activity Conducted';
      const tangibleDocs =
          'Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, receipts and photo Documentation';
      const tangibleNote =
          'Computation is accumulated amount. Consumables not included. Office equipment/equipment for the CSC use alone are not credited.';
      const coSponsor =
          'For activities conducted with co-sponsor, the points will be divided equally. Any Regional Activity conducted should have CHED Endorsement.';
      const pctDocs =
          'Supporting Documents: Copy of the approved Action Plan, Summary of Accomplishment Report';
      // ----- page-1 blocks -----
      pw.Widget infoField(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(children: [
          pw.Text(label, style: _sans(9)),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 2),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
              child: pw.Text(value, style: _sans(9)),
            ),
          ),
        ]),
      );

      List<pw.Widget> page1Head() => [
        pw.Center(
          child: pw.Text(
            'CRITERIA FOR THE SEARCH FOR OUTSTANDING $councilLabel SY $schoolYear',
            style: _sans(10, bold: true),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(children: [
          pw.Expanded(child: infoField('Organization:', orgName)),
          pw.SizedBox(width: 14),
          pw.Expanded(child: infoField('Points:', grandTotal.toStringAsFixed(2))),
        ]),
        pw.Row(children: [
          pw.Expanded(child: infoField('Campus:', campusLine)),
          pw.SizedBox(width: 14),
          pw.Expanded(child: infoField('Adjectival Rating:', adjectivalRating.toUpperCase())),
        ]),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text('ACTIVITIES CONDUCTED/ SPONSORED',
              style: _sans(9, bold: true).copyWith(decoration: pw.TextDecoration.underline)),
        ),
        pw.SizedBox(height: 10),
      ];

      pw.Widget sdgNote() => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
        child: pw.RichText(
          text: pw.TextSpan(style: _sans(7.5), children: [
            pw.TextSpan(text: 'For ', style: _sans(7.5)),
            pw.TextSpan(
                text: 'Items III, IV, V and VI, the number of SDGs is no longer required',
                style: _sans(7.5, bold: true)),
            pw.TextSpan(
                text: ', as discussed during the OSDW 3rd Quarter Meeting held last August 15, 2024. All activities under these items are now considered specific and aligned with their respective objectives.',
                style: _sans(7.5)),
          ]),
        ),
      );
  
      // ----- last-page blocks -----
      final grandTotalRow = pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text('Grand Total: ', style: _sans(11, bold: true)),
        pw.Text(_fmt(grandTotal), style: _sans(12, bold: true, color: _ink)),
      ]);


      String noted(String k, String d) {
        final v = (gridValues[k] ?? '').trim();
        return v.isEmpty ? d : v;
      }

      final List<pw.Widget> signatureBlock = [
        pw.Text('Certified True and Correct:', style: _sans(10, bold: true, italic: true)),
        pw.SizedBox(height: 30),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          _signatureCol('Signature over Printed name of Evaluator'),
          _signatureCol('Signature over Printed name of Evaluator'),
        ]),
        pw.SizedBox(height: 30),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          _signatureCol('Signature over Printed name of Evaluator'),
          _signatureCol('Signature over Printed name of Evaluator'),
        ]),
        pw.SizedBox(height: 30),
        pw.Text('Noted:', style: _sans(10, bold: true, italic: true)),
        pw.SizedBox(height: 18),
        pw.Text(noted('noted_name', 'LORAINE SUYU-TATTAO, Ph.D.'),
            style: _sans(11, bold: true).copyWith(decoration: pw.TextDecoration.underline)),
        pw.SizedBox(height: 2),
        pw.Text(noted('noted_title', 'University Director'), style: _sans(8, bold: true)),
        pw.Text(noted('noted_office', 'Office of the Student Services and Welfare'), style: _sans(8)),
      ];
  
      // =====================================================================
      // SPECIALIZED ORGANIZATION (4 pages)
      // =====================================================================
      if (isSpecialized) {
        addPage(1, [
          ...page1Head(),
          _buildSdgLegend(profile),
          cat('i'),
          cat('ii'),
          sdgNote(),
          _buildCategoricalPdfHeader(profile),
          cat('iii'),
        ]);
  
        addPage(2, [
          cat('iv'),
          pw.SizedBox(height: 8),
          note('Note: $coSponsor'),
          pw.SizedBox(height: 15),
          scoredHeading('V. Tangible/ Physical Projects (10 points)', 'v'),
          bullet(tangibleNote),
          bullet(tangibleDocs),
          pw.SizedBox(height: 6),
          amt(_standardAmountRows.sublist(0, 14), key: 'v', label: 'Amount (Php)'),
        ]);
  
        addPage(3, [
          amt(_standardAmountRows.sublist(14), key: 'v', header: false),
          pw.SizedBox(height: 15),
          scoredHeading('VI. Fund Drive/ IGP (10 points)', 'vi'),
          note(fundDocs),
          pw.SizedBox(height: 6),
          amt(_standardAmountRows, key: 'vi', label: 'Amount (Php)'),
        ]);
  
        addPage(4, [
          scoredHeading('VII. Percentage of Implementation of the Approved Action Plan (10 points)', 'vii'),
          note('Supporting Documents: Copy of the approved Action Plan, Summary of Accomplishment Report'),
          pw.SizedBox(height: 6),
          pct(_percentRows, 'vii'),
          pw.SizedBox(height: 14),
          _buildSummaryPdfTable(const [
            ['I. Symposium/ Seminars Conducted', '(20 points)', 'i'],
            ['II. Activities Conducted/ Sponsored in line with the nature of the organization', '(30 points)', 'ii'],
            ['III. Maka-kalikasan/ Clean and Green Activities and Projects', '(10 points)', 'iii'],
            ['IV. Extension Services Sponsored/Conducted', '(10 points)', 'iv'],
            ['V. Tangible/ Physical Projects', '(10 points)', 'v'],
            ['VI. Fund Drive/ IGP', '(10 points)', 'vi'],
            ['VII. Percentage of Implementation of the Approved Action Plan', '(10 points)', 'vii'],
          ], scores, centerHeader: false),
          pw.SizedBox(height: 10),
          grandTotalRow,
          pw.SizedBox(height: 20),
          ...signatureBlock,
        ]);
        return pdf;
      }
  
      // =====================================================================
      // CAMPUS / COLLEGE STUDENT COUNCIL (5 pages)
      // =====================================================================
      final summaryRows = const [
        ['I. Symposium/ Seminars Conducted', '(10 points)', 'i'],
        ['II. Convocations/Programs and Literary Activities', '(10 points)', 'ii'],
        ['III. Religious Activities', '(5 points)', 'iii'],
        ['IV. Socio-Cultural & Sports Activities', '(10 points)', 'iv'],
        ['V. Maka-kalikasan/Clean and Green Activities and Projects', '(10 points)', 'v'],
        ['VI. Extension Services Sponsored/Conducted', '(10 points)', 'vi'],
        ['VII. Tangible/ Physical Projects', '(15 points)', 'vii'],
        ['VIII. Fund Drive/ IGP', '(10 points)', 'viii'],
        ['IX. Financial Assistance given to members (medical aid, death aid and subsidy to seminar)', '(10 points)', 'ix'],
        ['X. Percentage of Implementation of the Approved Action Plan', '(10 points)', 'x'],
      ];
  
      final fundHeading = scoredHeading('VIII. Fund Drive/ IGP (10 points)', 'viii');
      final finHeading = scoredHeading(
          'IX. Financial Assistance given to members (subsidy to activities and to seminar (10 points)', 'ix');
      final pctHeading = scoredHeading(
          'X. Percentage of Implementation of the Approved Action Plan (10 points)', 'x');
  
      addPage(1, [
        ...page1Head(),
        _buildSdgLegend(profile),
        cat('i'),
        cat('ii'),
        sdgNote(),
        _buildCategoricalPdfHeader(profile),
        cat('iii'),
      ]);
  
      addPage(2, [
        cat('iv'),
        pw.SizedBox(height: 10),
        cat('v'),
        pw.SizedBox(height: 10),
        cat('vi'),
        pw.SizedBox(height: 8),
        note(coSponsor),
        pw.SizedBox(height: 15),
        scoredHeading('VII. Tangible/ Physical Projects (15 points)', 'vii'),
        bullet(tangibleNote),
        bullet(tangibleDocs),
        pw.SizedBox(height: 6),
        amt(_tangibleFirst, key: 'vii'),
      ]);

      if (isCampus) {
        addPage(3, [
          amt(_tangibleCont, key: 'vii', header: false),
          pw.SizedBox(height: 15),
          fundHeading, note(fundDocs), pw.SizedBox(height: 6),
          amt(_campusAmountRows.sublist(0, 16), key: 'viii'),
        ]);

        addPage(4, [
          amt(_campusAmountRows.sublist(16), key: 'viii', header: false),
          pw.SizedBox(height: 15),
          finHeading, note(finDocs), pw.SizedBox(height: 6),
          amt(_campusAmountRows, key: 'ix'),
          pw.SizedBox(height: 15),
          pctHeading, note(pctDocs), pw.SizedBox(height: 6),
          pct(_percentRows.sublist(0, 5), 'x'),
        ]);
        addPage(5, [
          pct(_percentRows.sublist(5), 'x', header: false),
          pw.SizedBox(height: 14),
          _buildSummaryPdfTable(summaryRows, scores),
          pw.SizedBox(height: 10),
          grandTotalRow,
          pw.SizedBox(height: 20),
          ...signatureBlock,
        ]);
      } else {
        addPage(3, [
          amt(_tangibleCont, key: 'vii', header: false),
          pw.SizedBox(height: 15),
          fundHeading, note(fundDocs), pw.SizedBox(height: 6),
          amt(_collegeFundRows, key: 'viii'),
          pw.SizedBox(height: 15),
          finHeading, note(finDocs), pw.SizedBox(height: 6),
          amt(_collegeFinRows.sublist(0, 3), key: 'ix'),
        ]);
        addPage(4, [
          amt(_collegeFinRows.sublist(3), key: 'ix', header: false),
          pw.SizedBox(height: 15),
          pctHeading, note(pctDocs), pw.SizedBox(height: 6),
          pct(_percentRows, 'x'),
          pw.SizedBox(height: 14),
          _buildSummaryPdfTable(summaryRows, scores),
          pw.SizedBox(height: 10),
          grandTotalRow,
        ]);
        addPage(5, [
          ...signatureBlock,
        ]);
      }
  
      return pdf;
    }
  
    // =====================================================================
    // SAVE / PREVIEW (unchanged)
    // =====================================================================
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

    static Future<void> printPdf({
      required Map<String, dynamic> organization,
      required String schoolYear,
      required Map<String, double> scores,
      required Map<String, String> gridValues,
      required double grandTotal,
      required String adjectivalRating,
      String orgType = 'College Student Council',
    }) async {
      await Printing.layoutPdf(
        name: '${organization['name'] ?? 'Evaluation'}_Evaluation_Sheet_SY_$schoolYear',
        format: PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch),
        onLayout: (format) async {
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
      );
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
                      const Text(
                        'EVALUATION SHEET PRINT PREVIEW (FOLIO 8.5 x 13.0 in)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                          OutlinedButton.icon(
                            onPressed: () async {
                              await printPdf(
                                organization: organization,
                                schoolYear: schoolYear,
                                scores: scores,
                                gridValues: gridValues,
                                grandTotal: grandTotal,
                                adjectivalRating: adjectivalRating,
                                orgType: orgType,
                              );
                            },
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text('Print'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981)),
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
                      pageFormats: {'Folio / Long Paper (8.5 x 13.0 in)': folioFormat},
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
  
    // =====================================================================
    // PAGE SHELL (letterhead + footer like the official forms)
    // =====================================================================
    static pw.Page _buildPage({
      required int pageNumber,
      required pw.ThemeData theme,
      required pw.ImageProvider? logo,
      required List<pw.Widget> content,
      required String footerLabel,
      required String schoolYear,
      bool isCampus = false,
      bool isSpecialized = false,
    }) {
      final campusHeader = isSpecialized ? 'ANDREWS CAMPUS' : (isCampus ? 'Central Administration' : 'LAL-LO CAMPUS');
      final locationHeader = isSpecialized
          ? 'Caritan, Tuguegarao City, Cagayan'
          : (isCampus ? 'Caritan, Tuguegarao City, Cagayan' : 'Sta. Maria, Lal-lo, Cagayan');
      final emailHeader = isSpecialized ? 'osdw@csu.edu.ph' : (isCampus ? 'osdw@csu.edu.ph' : 'osdw.lallo@csu.edu.ph');
      final fbHeader = isSpecialized
          ? 'Ossw Andrews'
          : (isCampus ? 'CSU Office of Student Development & Welfare' : 'Osdw Lallo');
      final red = PdfColor.fromHex('#B71C1C');
      pw.TextStyle s(double z, {bool b = false, bool i = false, bool u = false}) =>
          _serif(z, bold: b, italic: i, color: red, underline: u);

      return pw.Page(
        pageFormat: PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch),
        theme: theme,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('REPUBLIC OF THE PHILIPPINES', style: s(8)),
                  pw.Text('CAGAYAN STATE UNIVERSITY', style: s(9, b: true)),
                  pw.Text(campusHeader, style: s(8)),
                  pw.Text(locationHeader, style: s(8, i: true)),
                ]),
              ),
              pw.Container(
                width: 65,
                child: pw.Center(
                  child: logo != null
                      ? pw.Container(height: 55, width: 55, child: pw.Image(logo))
                      : pw.SizedBox(width: 55, height: 55),
                ),
              ),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.RichText(text: pw.TextSpan(children: [
                    pw.TextSpan(text: 'Email Address: ', style: s(8, i: true)),
                    pw.TextSpan(text: emailHeader, style: s(8, i: true, u: true)),
                  ])),
                  pw.RichText(text: pw.TextSpan(children: [
                    pw.TextSpan(text: 'Website: ', style: s(8, i: true)),
                    pw.TextSpan(text: 'www.csu.edu.ph', style: s(8, i: true, u: true)),
                  ])),
                  pw.Text('Facebook Page: $fbHeader', style: s(8, i: true)),
                ]),
              ),
            ]),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text('OFFICE OF STUDENT DEVELOPMENT AND WELFARE',
                  style: _serif(13, bold: true, color: PdfColors.black)),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1.5, color: PdfColors.black),
            pw.SizedBox(height: 8),
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: content)),
            pw.Divider(thickness: 0.5, color: PdfColors.grey500),
            pw.SizedBox(height: 4),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text('$pageNumber | ', style: _sans(9, bold: true)),
              pw.Text('P a g e  ', style: _sans(9, color: PdfColors.grey600)),
              pw.Text('Search for the Most Outstanding $footerLabel SY $schoolYear',
                  style: _sans(9, bold: true)),
            ]),
          ],
        ),
      );
    }
  
    // =====================================================================
    // SDG LEGEND (No. of SDGs / Pts) + HEADERS
    // =====================================================================
    static pw.Widget _buildSdgLegend(String profile) {
      final tiers = _tiers[profile]!;
      final n = _levels(profile).length;
      var maxRows = 0;
      for (var i = 0; i < n; i++) {
        if (tiers[i].length > maxRows) maxRows = tiers[i].length;
      }
      final noteStart = maxRows > 3 ? 3 : maxRows - 1;
      const h1 = 42.0, h2 = 28.0, rh = 15.0;
      final topH = h1 + h2 + noteStart * rh;

      pw.Widget split(double h, pw.Widget a, pw.Widget b) => pw.Row(children: [
        pw.Expanded(child: _box(height: h, child: a)),
        pw.Expanded(child: _box(height: h, child: b)),
      ]);

      return pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(left: _bs, top: _bs)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(
            width: _wA + _wB,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(children: [
                _box(width: _wA, height: topH, child: pw.Text('Activities', style: _sans(9, bold: true))),
                _box(width: _wB, height: topH,
                    child: pw.Text('Supporting\nDocuments', style: _sans(9, bold: true), textAlign: pw.TextAlign.center)),
              ]),
              _box(
                width: _wA + _wB, height: (maxRows - noteStart) * rh, pad: const pw.EdgeInsets.all(3),
                child: pw.Text('Attendance should be 50%+1 of the total target participants.',
                    style: _sans(5.5, italic: true), textAlign: pw.TextAlign.center),
              ),
            ]),
          ),
          for (var i = 0; i < n; i++)
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                _box(
                  height: h1, pad: const pw.EdgeInsets.all(2),
                  child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                    pw.Text(kLevelTitles[i], style: _sans(6.5, bold: true), textAlign: pw.TextAlign.center),
                    if (i == 0)
                      pw.Text(kIntlNote, style: _sans(5.2, italic: true), textAlign: pw.TextAlign.center),
                  ]),
                ),
                split(h2,
                    pw.Text('No.\nof\nSDGs', style: _sans(5.5), textAlign: pw.TextAlign.center),
                    pw.Text('Pts', style: _sans(6.5, bold: true))),
                for (var r = 0; r < maxRows; r++)
                  r < tiers[i].length
                      ? split(rh,
                      pw.Text(formatTier(tiers[i][r][0]), style: _sans(6.5)),
                      pw.Text(formatTier(tiers[i][r][1]), style: _sans(6.5, bold: true)))
                      : split(rh, pw.SizedBox(), pw.SizedBox()),
              ]),
            ),
        ]),
      );
    }
    /// Header for items that are NOT SDG-based (flat points per level).
    static pw.Widget _buildCategoricalPdfHeader(String profile) {
      final n = _levels(profile).length;
      final pts = profile == 'campus' ? _levelPtsCampus : _levelPtsSpecCollege;
      return pw.Container(
        height: 48,
        decoration: const pw.BoxDecoration(border: pw.Border(left: _bs, top: _bs)),
        child: pw.Row(children: [
          _box(width: _wA, height: 48, child: pw.Text('Activities', style: _sans(9, bold: true))),
          _box(width: _wB, height: 48,
              child: pw.Text('Supporting\nDocuments', style: _sans(9, bold: true), textAlign: pw.TextAlign.center)),
          for (var i = 0; i < n; i++)
            pw.Expanded(
              child: _box(
                height: 48, pad: const pw.EdgeInsets.all(2),
                child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                  pw.Text(kLevelTitles[i], style: _sans(6.5, bold: true), textAlign: pw.TextAlign.center),
                  if (i == 0) pw.Text(kIntlNote, style: _sans(5.2, italic: true), textAlign: pw.TextAlign.center),
                  pw.Text(pts[i], style: _sans(6.5, bold: true), textAlign: pw.TextAlign.center),
                ]),
              ),
            ),
        ]),
      );
    }
  
    // =====================================================================
    // CATEGORY TABLE: one row per activity inside every level column,
    // plus a TOTAL PER LEVEL row.
    // =====================================================================
    static pw.Widget _buildActivityCategoryPdfTable({
      required String profile,
      required _CatDef def,
      required Map<String, String> gridValues,
      required double score,
    }) {
      final levels = _levels(profile);

      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: _cols(profile),
        children: [
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.Container(padding: const pw.EdgeInsets.all(5), child: _categoryTitle(def.title)),
              pw.Container(padding: const pw.EdgeInsets.all(5), child: pw.Text(def.docs, style: _sans(6.2))),
              for (final lvl in levels) _levelTotalGridCell(profile, def, lvl, gridValues),
            ],
          ),
        ],
      );
    }
    static List<pw.TextSpan> _digitSpans(String s) {
      final out = <pw.TextSpan>[];
      s.splitMapJoin(RegExp(r'\d+'),
          onMatch: (m) { out.add(pw.TextSpan(text: m[0], style: _sans(6, bold: true))); return ''; },
          onNonMatch: (t) { if (t.isNotEmpty) out.add(pw.TextSpan(text: t, style: _sans(6))); return ''; });
      return out;
    }

    static pw.Widget _categoryTitle(String raw) {
      final lines = raw.split('\n');
      final m = RegExp(r'^([IVX]+\.)\s*(.*?)\s*(\(\d+ points\))\s*$').firstMatch(lines.first);
      final maxLine = lines.length > 1 ? lines.sublist(1).join(' ') : '';
      pw.Widget b(String t) => pw.Text(t, style: _sans(8, bold: true), textAlign: pw.TextAlign.center);
      return pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
        if (m != null) ...[b(m.group(1)!), b(m.group(2)!), b(m.group(3)!)] else b(lines.first),
        if (maxLine.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.RichText(textAlign: pw.TextAlign.center, text: pw.TextSpan(children: _digitSpans(maxLine))),
          ),
      ]);
    }

    static pw.Widget _levelTotalGridCell(String profile, _CatDef def, String lvl, Map<String, String> g) {
      final pts = _levelTotal(profile, def, lvl, g);
      return pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(
          pts > 0 ? _fmt(pts) : '',
          style: _sans(11, bold: true, color: _ink),
          textAlign: pw.TextAlign.center,
        ),
      );
    }

  

  
    // =====================================================================
    // AMOUNT / PERCENTAGE TABLES
    // =====================================================================
    static pw.Widget _buildMappingPdfTable(
        List<List<String>> rows, {
          String headerLabel = 'Amount',
          double currentScore = 0,
          bool showHeader = true,
        }) {
      final table = pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FixedColumnWidth(80)},
        children: [
          if (showHeader)
            pw.TableRow(children: [
              pw.Container(padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(headerLabel, style: _sans(8, bold: true), textAlign: pw.TextAlign.center)),
              pw.Container(padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('Points', style: _sans(8, bold: true), textAlign: pw.TextAlign.center)),
            ]),
          ...rows.map((r) {
            final hit = currentScore > 0 && (double.tryParse(r[1]) ?? -1) == currentScore;
            return pw.TableRow(
              decoration: hit ? pw.BoxDecoration(color: _hit) : null,
              children: [
                pw.Container(padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(r[0], style: _sans(7, bold: hit), textAlign: pw.TextAlign.center)),
                pw.Container(padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(r[1], style: _sans(7, bold: true, color: hit ? _ink : null), textAlign: pw.TextAlign.center)),
              ],
            );
          }),
        ],
      );
      return pw.Center(child: pw.SizedBox(width: 300, child: table));
    }
    /// Official style: plain "94%-100% : 10" list; the achieved band is shaded.
    static pw.Widget _buildPercentageList(List<List<String>> rows, {double currentScore = 0, bool showHeader = true}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(left: 18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              pw.Text('Percentage of Implementation Points', style: _sans(10, bold: true)),
              pw.SizedBox(height: 3),
            ],
            for (final r in rows)
              pw.Container(
                width: 150,
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                decoration: (currentScore > 0 && (double.tryParse(r[1]) ?? -1) == currentScore)
                    ? pw.BoxDecoration(color: _hit)
                    : null,
                child: pw.Row(children: [
                  pw.SizedBox(width: 70, child: pw.Text(r[0], style: _sans(9))),
                  pw.SizedBox(width: 20, child: pw.Text(':', style: _sans(9))),
                  pw.Text(r[1], style: _sans(9, bold: true)),
                ]),
              ),
          ],
        ),
      );
    }
  
    // =====================================================================
    // SUMMARY (Sub Categories / Score)
    // =====================================================================
    static pw.Widget _buildSummaryPdfTable(List<List<String>> rows, Map<String, double> scores, {bool centerHeader = true}) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 1),
        columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FixedColumnWidth(80)},
        children: [
          pw.TableRow(children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              alignment: centerHeader ? pw.Alignment.center : pw.Alignment.centerLeft,
              child: pw.Text('Sub Categories', style: _sans(9, bold: true)),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              alignment: pw.Alignment.center,
              child: pw.Text('Score', style: _sans(9, bold: true)),
            ),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              child: pw.RichText(
                text: pw.TextSpan(style: _sans(8), children: [
                  pw.TextSpan(text: '${r[0]} ', style: _sans(8)),
                  pw.TextSpan(text: r[1], style: _sans(8, bold: true)),
                ]),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              alignment: pw.Alignment.center,
              child: pw.Text(_fmt(scores[r[2]] ?? 0), style: _sans(8, bold: true, color: _ink)),
            ),
          ])),
        ],
      );
    }
  
    // =====================================================================
    // SMALL WIDGETS
    // =====================================================================

    static pw.Widget _signatureCol(String label) {
      return pw.Column(
        children: [
          pw.Container(width: 180, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
          pw.SizedBox(height: 3),
          pw.Text(label, style: _sans(7)),
        ],
      );
    }
  }