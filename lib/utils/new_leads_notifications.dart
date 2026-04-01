import '../models/lead.dart';
import 'new_leads_notifications_stub.dart'
    if (dart.library.html) 'new_leads_notifications_web.dart'
    if (dart.library.io) 'new_leads_notifications_io.dart' as impl;

/// Call once from [main] after [WidgetsFlutterBinding.ensureInitialized].
Future<void> initNewLeadNotifications() => impl.initNewLeadNotifications();

/// Shows a system / browser notification for one or more new leads.
Future<void> showNewLeadNotifications(List<Lead> leads) =>
    impl.showNewLeadNotifications(leads);
