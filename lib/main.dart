import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_navigator.dart';
import 'data/app_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'utils/new_leads_notifications.dart';
import 'widgets/delivery_completion_notification_listener.dart';
import 'widgets/new_leads_notification_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNewLeadNotifications();
  final repo = AppRepository();
  await repo.initFirebase();
  runApp(
    ChangeNotifierProvider(
      create: (_) => repo,
      child: const FruitBasketApp(),
    ),
  );
}

class FruitBasketApp extends StatelessWidget {
  const FruitBasketApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Do not `watch` AppRepository here — every Firestore customer update would
    // rebuild MaterialApp and destabilize Navigator / route overlays (dialogs).
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Fruit Basket',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _AuthGate(),
    );
  }
}

/// Login vs main shell; only this subtree rebuilds on [AppRepository] changes.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return repo.isLoggedIn
        ? const NewLeadsNotificationListener(
            child: DeliveryCompletionNotificationListener(
              child: HomeShell(),
            ),
          )
        : const LoginScreen();
  }
}
