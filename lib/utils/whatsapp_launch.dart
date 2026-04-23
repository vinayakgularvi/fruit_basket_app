import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_navigator.dart';
import '../models/customer.dart';
import 'phone_launch.dart';
import 'payment_receipt_pdf.dart';
import 'schedule_after_frame.dart';

/// Pre-filled text for customers whose subscription ends today (delivery reminder).
String subscriptionLastDayRenewalWhatsAppMessage() {
  return 'Dear Customer,\n\n'
      "We hope you're enjoying your experience with Fruit Basket.\n\n"
      'This is a quick reminder that your subscription expires today. '
      'Kindly let us know if you would like to:\n'
      '* Continue your current plan\n'
      '* Upgrade to a premium plan\n'
      '* Cancel your subscription\n\n'
      'Please reply at your convenience so we can assist you without any '
      'interruption in service.\n\n'
      'Thank you for choosing Fruit Basket.\n\n'
      'Warm regards,\n'
      'Team Fruit Basket';
}

/// Opens WhatsApp chat to [phone] with [subscriptionLastDayRenewalWhatsAppMessage].
Future<void> openSubscriptionExpiryWhatsApp(
  BuildContext context,
  String phone,
) async {
  var digits = sanitizedPhoneForDial(phone).replaceAll('+', '');
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

  final text = subscriptionLastDayRenewalWhatsAppMessage();
  final uri = Uri(
    scheme: 'https',
    host: 'wa.me',
    path: '/$digits',
    queryParameters: <String, String>{'text': text},
  );

  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  final root = rootNavigatorContext;
  final snackCtx = root != null && root.mounted ? root : context;
  if (!snackCtx.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(snackCtx).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp')),
    );
  }
}

/// Reminder for outstanding period payment (amount is always the current remaining).
String buildPaymentPendingWhatsAppMessage(int remainingRupees) {
  final amt = NumberFormat.decimalPattern('en_IN').format(remainingRupees);
  return 'Dear Customer,\n\n'
      'A payment of ₹$amt is pending. Kindly complete it at your earliest convenience.\n\n'
      'Thank you,\n'
      'Team Fruit Basket';
}

/// Opens WhatsApp with [buildPaymentPendingWhatsAppMessage] for [remainingRupees].
Future<void> openPaymentPendingWhatsApp(
  BuildContext context, {
  required String phone,
  required int remainingRupees,
}) async {
  var digits = sanitizedPhoneForDial(phone).replaceAll('+', '');
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

  final text = buildPaymentPendingWhatsAppMessage(remainingRupees);
  final uri = Uri(
    scheme: 'https',
    host: 'wa.me',
    path: '/$digits',
    queryParameters: <String, String>{'text': text},
  );

  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  final root = rootNavigatorContext;
  final snackCtx = root != null && root.mounted ? root : context;
  if (!snackCtx.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(snackCtx).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp')),
    );
  }
}

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
