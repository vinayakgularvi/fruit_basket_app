import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// First http(s) URL in [text] (e.g. pasted Google Maps share link + notes below).
Uri? mapsUriFromAddress(String text) {
  final match = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  final group = match.group(0);
  if (group == null || group.isEmpty) return null;
  var s = group;
  while (s.endsWith(')') || s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return null;
  return Uri.tryParse(s);
}

/// Opens [uri] in the browser / Maps app.
Future<bool> launchMapsUri(Uri uri) async {
  const mode =
      kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
  return launchUrl(uri, mode: mode);
}

Future<void> openAddressInGoogleMaps(
  BuildContext context,
  String address,
) async {
  final uri = mapsUriFromAddress(address);
  if (uri == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No link found. Add a Google Maps URL in the customer address.',
        ),
      ),
    );
    return;
  }
  final ok = await launchMapsUri(uri);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Maps')),
    );
  }
}
