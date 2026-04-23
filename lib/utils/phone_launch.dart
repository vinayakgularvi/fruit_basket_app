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

/// Digits only (no `+`), for comparisons.
String phoneDigitsOnly(String raw) =>
    raw.replaceAll(RegExp(r'\D'), '');

/// Last 10 digits when at least 10 are present (typical mobile); otherwise full digit run.
String phoneMatchKey(String raw) {
  final d = phoneDigitsOnly(raw);
  if (d.length >= 10) return d.substring(d.length - 10);
  return d;
}

/// Whether [Lead.mobile] is the same number as [customerPhone] (dedupe after signup).
bool leadMobileMatchesCustomerPhone(String mobile, String customerPhone) {
  final m = mobile.trim();
  if (m.isEmpty) return false;
  final ck = phoneMatchKey(customerPhone);
  if (ck.isEmpty) return false;
  final mk = phoneMatchKey(m);
  if (mk.length >= 10 && ck.length >= 10) return mk == ck;
  return phoneDigitsOnly(m) == phoneDigitsOnly(customerPhone);
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
