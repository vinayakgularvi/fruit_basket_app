import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import 'schedule_after_frame.dart';

const _kBusinessName = 'Fruit Basket';
const _kBusinessAddress =
    'Near Maruthi Nagar Arch, Settihalli Main Road Tumakuru 572102';

String _safeFilePart(String input) {
  final sanitized = input.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').trim();
  return sanitized.isEmpty ? 'customer' : sanitized;
}

/// Indian rupee sign + spaced amount (PDF default fonts often omit ₹).
String _formatRupee(int rupees) {
  final n = NumberFormat.decimalPattern('en_IN');
  return '₹ ${n.format(rupees)}';
}

Future<void> downloadPaymentReceiptPdf({
  required Customer customer,
  required int collectedAmountRupees,
  required String paymentLabel,
  required DateTime collectedAt,
  String? collectedBy,
}) async {
  final file = await generatePaymentReceiptPdfFile(
    customer: customer,
    collectedAmountRupees: collectedAmountRupees,
    paymentLabel: paymentLabel,
    collectedAt: collectedAt,
    collectedBy: collectedBy,
  );
  await scheduleAfterFrame(() async {
    await Printing.sharePdf(bytes: file.bytes, filename: file.fileName);
    return null;
  });
}

Future<({Uint8List bytes, String fileName})> generatePaymentReceiptPdfFile({
  required Customer customer,
  required int collectedAmountRupees,
  required String paymentLabel,
  required DateTime collectedAt,
  String? collectedBy,
}) async {
  final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
  final doc = pw.Document();
  final receiptNo = 'FB-${DateFormat('yyMMddHHmmss').format(collectedAt)}';
  final baseFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  final amountStr = _formatRupee(collectedAmountRupees);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
      ),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#2E7D32'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          _kBusinessName,
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _kBusinessAddress,
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#A5D6A7'),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Text(
                      'PAID',
                      style: pw.TextStyle(
                        color: PdfColor.fromHex('#1B5E20'),
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Payment Receipt',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Receipt No: $receiptNo',
              style: pw.TextStyle(
                color: PdfColor.fromHex('#616161'),
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromHex('#DADADA')),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                color: PdfColor.fromHex('#F7FBF7'),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Customer: ${customer.name}'),
                  pw.Text('Phone: ${customer.phone}'),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#FFF8E1'),
                border: pw.Border.all(color: PdfColor.fromHex('#FFC107')),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Amount collected',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#5D4037'),
                    ),
                  ),
                  pw.Text(
                    amountStr,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#2E7D32'),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0')),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(3),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#E8F5E9'),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Field',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Details',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                _row('Payment for', paymentLabel),
                _row('Collected at', dateFmt.format(collectedAt)),
                if (collectedBy != null && collectedBy.trim().isNotEmpty)
                  _row('Collected by', collectedBy.trim()),
              ],
            ),
            if (collectedBy != null && collectedBy.trim().isNotEmpty)
              pw.SizedBox(height: 10),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Generated by Fruit Basket app',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        );
      },
    ),
  );

  final fileDate = DateFormat('yyyyMMdd_HHmmss').format(collectedAt);
  final fileName =
      'Fruit_Basket_Receipt_${_safeFilePart(customer.name)}_$fileDate.pdf';
  final bytes = await doc.save();
  return (bytes: bytes, fileName: fileName);
}

pw.TableRow _row(String k, String v) {
  return pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(k),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(v),
      ),
    ],
  );
}
