import '../models/delivery_completion_event.dart';
import 'delivery_completion_notifications_stub.dart'
    if (dart.library.html) 'delivery_completion_notifications_web.dart'
    if (dart.library.io) 'delivery_completion_notifications_io.dart' as impl;

Future<void> showDeliveryCompletionNotifications(
  List<DeliveryCompletionEvent> events,
) =>
    impl.showDeliveryCompletionNotifications(events);
