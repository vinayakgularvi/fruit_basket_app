import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/delivery_completion_event.dart';
import 'delivery_completion_notification_content.dart';
import 'local_notifications_plugin.dart';

const _deliveryChannelId = 'fruit_basket_delivery_updates';
const _deliveryChannelName = 'Delivery updates';
const _deliveryChannelDesc = 'When a delivery agent marks deliveries complete';

Future<void> showDeliveryCompletionNotifications(
  List<DeliveryCompletionEvent> events,
) async {
  final content = deliveryCompletionNotificationContent(events);
  if (content == null) return;

  final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);

  await localNotificationsPlugin.show(
    id: id,
    title: content.title,
    body: content.body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _deliveryChannelId,
        _deliveryChannelName,
        channelDescription: _deliveryChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}
