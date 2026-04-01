import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/lead.dart';
import 'new_leads_notifications_content.dart';

/// Uses the browser [Notifications API](https://developer.mozilla.org/en-US/docs/Web/API/Notifications_API).
/// Requires a [secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts)
/// (HTTPS or localhost).
Future<void> initNewLeadNotifications() async {
  try {
    if (!web.window.isSecureContext) return;
    final perm = web.Notification.permission;
    if (perm == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  } catch (_) {
    // Unsupported or blocked.
  }
}

Future<void> showNewLeadNotifications(List<Lead> leads) async {
  final content = newLeadsNotificationContent(leads);
  if (content == null) return;
  if (!web.window.isSecureContext) return;
  if (web.Notification.permission != 'granted') return;
  try {
    web.Notification(
      content.title,
      web.NotificationOptions(
        body: content.body,
        tag: 'fruit_basket_new_leads',
      ),
    );
  } catch (_) {
    // Ignore if still blocked or API unavailable.
  }
}
