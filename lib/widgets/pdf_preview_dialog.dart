import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:csuatlasf/utils/pdf_generator.dart';

class GPOAPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> organization;
  final List<Map<String, dynamic>> activities;
  final Map<String, dynamic>? president;
  final Map<String, dynamic>? adviser;
  final String fileName;

  const GPOAPreviewDialog({
    super.key,
    required this.organization,
    required this.activities,
    required this.president,
    required this.adviser,
    this.fileName = 'GPOA_Report.pdf',
  });

  @override
  Widget build(BuildContext context) {
    // Standard Folio (Long Bond Paper) 8.5" x 13"
    final folioFormat = PdfPageFormat(8.5 * PdfPageFormat.inch, 13.0 * PdfPageFormat.inch).landscape;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.95,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GPOA Report Preview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                    Text('Standard Folio (Long Bond Paper) 8.5x13in Layout.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFF8FAFC)),
                ),
              ],
            ),
            const Divider(height: 32, color: Color(0xFFF1F5F9)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PdfPreview(
                  build: (format) async {
                    // Force the generator to use the Folio Landscape format
                    return (await GPOAPdfGenerator.generateGPOADocument(
                      organization: organization,
                      activities: activities,
                      president: president,
                      adviser: adviser,
                      format: folioFormat,
                    )).save();
                  },
                  allowPrinting: true,
                  allowSharing: true,
                  canChangePageFormat: true, // Allow user to see the size choice
                  canChangeOrientation: false,
                  initialPageFormat: folioFormat,
                  pdfFileName: fileName,
                  // Restrict to ONLY Folio size as requested
                  pageFormats: {
                    'Folio (Long) 8.5x13in': folioFormat,
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
