import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/lead.dart';
import 'new_leads_notifications_content.dart';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

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
  await _plugin.initialize(settings: settings);

  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    ),
  );
  await android?.requestNotificationsPermission();
}

Future<void> showNewLeadNotifications(List<Lead> leads) async {
  final content = newLeadsNotificationContent(leads);
  if (content == null) return;

  final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);

  await _plugin.show(
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
