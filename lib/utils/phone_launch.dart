import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keeps leading `+` and ASCII digits only (works for `tel:` URIs).
String sanitizedPhoneForDial(String phone) {
  final b = StringBuffer();
  for (var i = 0; i < phone.length; i++) {
    final code = phone.codeUnitAt(i);
    if (code == 0x2B) {
      b.write('+');
    } else if (code >= 0x30 && code <= 0x39) {
      b.writeCharCode(code);
    }
  }
  return b.toString();
}

Future<void> openCustomerPhoneDialer(BuildContext context, String phone) async {
  final clean = sanitizedPhoneForDial(phone);
  if (clean.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No digits in phone number to call')),
    );
    return;
  }
  final uri = Uri(scheme: 'tel', path: clean);
  final ok = await launchUrl(
    uri,
    mode: kIsWeb
        ? LaunchMode.externalApplication
        : LaunchMode.externalApplication,
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not start phone call')),
    );
  }
}
