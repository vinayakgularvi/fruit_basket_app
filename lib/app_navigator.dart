import 'package:flutter/material.dart';

/// Root navigator for dialogs/snackbars so async work after Firestore updates
/// does not use a stale [BuildContext] from a ListView item or tab subtree.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

BuildContext? get rootNavigatorContext => rootNavigatorKey.currentContext;
