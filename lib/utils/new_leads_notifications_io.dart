import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/lead.dart';
import 'local_notifications_plugin.dart';
import 'new_leads_notifications_content.dart';

const _channelId = 'fruit_basket_new_leads';
const _channelName = 'New leads';
const _channelDesc = 'Alerts when new leads arrive from Firestore';

Future<void> initNewLeadNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  );
  await localNotificationsPlugin.initialize(settings: settings);

  final android = localNotificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    ),
  );
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _deliveryChannelId,
      _deliveryChannelName,
      description: _deliveryChannelDesc,
      importance: Importance.defaultImportance,
    ),
  );
  await android?.requestNotificationsPermission();
}

const _deliveryChannelId = 'fruit_basket_delivery_updates';
const _deliveryChannelName = 'Delivery updates';
const _deliveryChannelDesc = 'When a delivery agent marks deliveries complete';

Future<void> showNewLeadNotifications(List<Lead> leads) async {
  final content = newLeadsNotificationContent(leads);
  if (content == null) return;

  final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);

  await localNotificationsPlugin.show(
    id: id,
    title: content.title,
    body: content.body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
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
