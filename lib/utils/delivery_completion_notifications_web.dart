import 'package:web/web.dart' as web;

import '../models/delivery_completion_event.dart';
import 'delivery_completion_notification_content.dart';

Future<void> showDeliveryCompletionNotifications(
  List<DeliveryCompletionEvent> events,
) async {
  final content = deliveryCompletionNotificationContent(events);
  if (content == null) return;
  if (!web.window.isSecureContext) return;
  if (web.Notification.permission != 'granted') return;
  try {
    web.Notification(
      content.title,
      web.NotificationOptions(
        body: content.body,
        tag: 'fruit_basket_delivery_updates',
      ),
    );
  } catch (_) {}
}
