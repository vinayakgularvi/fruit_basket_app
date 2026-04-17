import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/delivery_completion_event.dart';
import '../utils/delivery_completion_notifications.dart';

/// Subscribes to [AppRepository.newDeliveryCompletions] and shows local
/// notifications on admin devices when a delivery agent marks deliveries done.
class DeliveryCompletionNotificationListener extends StatefulWidget {
  const DeliveryCompletionNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<DeliveryCompletionNotificationListener> createState() =>
      _DeliveryCompletionNotificationListenerState();
}

class _DeliveryCompletionNotificationListenerState
    extends State<DeliveryCompletionNotificationListener> {
  StreamSubscription<List<DeliveryCompletionEvent>>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;
    final repo = context.read<AppRepository>();
    _sub?.cancel();
    _sub = repo.newDeliveryCompletions.listen((events) {
      if (!repo.isAdmin) return;
      unawaited(showDeliveryCompletionNotifications(events));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
