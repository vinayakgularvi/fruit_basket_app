import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app_navigator.dart';
import '../models/customer.dart';
import 'phone_launch.dart';
import 'payment_receipt_pdf.dart';
import 'schedule_after_frame.dart';

String buildReceiptWhatsAppMessage({
  required Customer customer,
  required int collectedAmountRupees,
  required String paymentLabel,
  required DateTime collectedAt,
  String? collectedBy,
}) {
  final when = '${collectedAt.day.toString().padLeft(2, '0')}-'
      '${collectedAt.month.toString().padLeft(2, '0')}-'
      '${collectedAt.year} '
      '${collectedAt.hour.toString().padLeft(2, '0')}:'
      '${collectedAt.minute.toString().padLeft(2, '0')}';
  final by = (collectedBy == null || collectedBy.trim().isEmpty)
      ? ''
      : '\nCollected by: ${collectedBy.trim()}';
  final amountLabel =
      '₹ ${NumberFormat.decimalPattern('en_IN').format(collectedAmountRupees)}';
  return 'Fruit Basket Receipt\n'
      'Customer: ${customer.name}\n'
      'Amount collected: $amountLabel\n'
      'For: $paymentLabel\n'
      'Date: $when$by\n'
      'Address: Near Maruthi Nagar Arch, Settihalli Main Road Tumakuru 572102';
}

Future<void> sendReceiptToWhatsApp(
  BuildContext context, {
  required Customer customer,
  required int collectedAmountRupees,
  required String paymentLabel,
  required DateTime collectedAt,
  String? collectedBy,
}) async {
  var digits = sanitizedPhoneForDial(customer.phone).replaceAll('+', '');
  if (digits.isEmpty) {
    final root = rootNavigatorContext;
    final snackCtx = root != null && root.mounted ? root : context;
    if (!snackCtx.mounted) return;
    ScaffoldMessenger.of(snackCtx).showSnackBar(
      const SnackBar(content: Text('No valid WhatsApp number for this customer')),
    );
    return;
  }
  if (digits.length == 10) {
    digits = '91$digits';
  }

  final text = buildReceiptWhatsAppMessage(
    customer: customer,
    collectedAmountRupees: collectedAmountRupees,
    paymentLabel: paymentLabel,
    collectedAt: collectedAt,
    collectedBy: collectedBy,
  );

  final receipt = await generatePaymentReceiptPdfFile(
    customer: customer,
    collectedAmountRupees: collectedAmountRupees,
    paymentLabel: paymentLabel,
    collectedAt: collectedAt,
    collectedBy: collectedBy,
  );
  final root = rootNavigatorContext;
  final shareCtx = root != null && root.mounted ? root : context;
  if (!shareCtx.mounted) return;
  await scheduleAfterFrame(() async {
    final r = rootNavigatorContext;
    final ctx = r != null && r.mounted ? r : shareCtx;
    if (!ctx.mounted) return null;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            receipt.bytes,
            name: receipt.fileName,
            mimeType: 'application/pdf',
          ),
        ],
        // User picks WhatsApp (or another app) from the share sheet.
        text: '$text\n\nWhatsApp number: +$digits',
        subject: 'Fruit Basket Payment Receipt',
      ),
    );
    return null;
  });
}
