import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/lead.dart';
import '../utils/new_leads_notifications.dart';

/// Subscribes to [AppRepository.newLeads] and shows local notifications while logged in.
class NewLeadsNotificationListener extends StatefulWidget {
  const NewLeadsNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<NewLeadsNotificationListener> createState() =>
      _NewLeadsNotificationListenerState();
}

class _NewLeadsNotificationListenerState
    extends State<NewLeadsNotificationListener> {
  StreamSubscription<List<Lead>>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;
    final repo = context.read<AppRepository>();
    _sub?.cancel();
    _sub = repo.newLeads.listen((leads) {
      unawaited(showNewLeadNotifications(leads));
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
